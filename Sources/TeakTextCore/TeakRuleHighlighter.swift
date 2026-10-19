import Foundation

/// Deterministic lexer with sparse state checkpoints. No regular-expression backtracking.
public actor TeakRuleHighlighter: TeakTextPlugin {
    public nonisolated let id: String
    private let language: TeakLanguageDefinition
    private let keywords: [String: String]
    private let lineComments: [[UInt16]]
    private let delimiters: [TeakCompiledDelimiter]
    private let identifierRules: [TeakCompiledIdentifierRule]
    private let identifierCharacters: Set<UInt16>
    private let linePrefixes: [(start: [UInt16], scope: String)]
    private var documentID: UUID?
    private var revision: UInt64 = 0
    private var checkpoints = [TeakLexerCheckpoint(offset: 0, state: .normal)]

    public init(language: TeakLanguageDefinition) throws {
        try language.validate()
        self.language = language
        id = "lexical.\(language.id)"
        var words: [String: String] = [:]
        for scope in language.keywords.keys.sorted() {
            for word in language.keywords[scope] ?? [] {
                words[language.caseInsensitiveKeywords == true ? word.lowercased() : word] = scope
            }
        }
        keywords = words
        lineComments = language.lineComments.sorted { $0.utf16.count > $1.utf16.count }.map { Array($0.utf16) }
        delimiters = (language.blockComments + language.strings)
            .sorted { $0.start.utf16.count > $1.start.utf16.count }
            .map { TeakCompiledDelimiter(start: Array($0.start.utf16), end: Array($0.end.utf16),
                escape: $0.escape?.utf16.first, multiline: $0.multiline, scope: $0.scope,
                nested: $0.nested == true, characterLiteral: $0.characterLiteral == true) }
        identifierCharacters = Set((language.identifierCharacters ?? "").utf16)
        identifierRules = (language.identifierRules ?? []).map {
            TeakCompiledIdentifierRule(precededBy: ($0.precededBy ?? []).map { Array($0.utf16) },
                followedBy: ($0.followedBy ?? []).map { Array($0.utf16) },
                startsWith: ($0.startsWith ?? []).map { Array($0.utf16) }, scope: $0.scope)
        }
        linePrefixes = (language.linePrefixes ?? []).sorted { $0.start.utf16.count > $1.start.utf16.count }
            .map { (Array($0.start.utf16), $0.scope) }
    }

    public func highlights(for request: TeakHighlightRequest) throws -> [TeakHighlightSpan] {
        try Task.checkCancellation()
        guard request.range.location >= 0, request.range.length >= 0,
              request.range.location <= request.snapshot.utf16Count,
              request.range.length <= request.snapshot.utf16Count - request.range.location else {
            throw TeakTextError.invalidRange
        }
        if documentID != request.documentID {
            documentID = request.documentID
            checkpoints = [TeakLexerCheckpoint(offset: 0, state: .normal)]
        } else if request.revision < revision {
            throw CancellationError()
        } else if request.revision != revision {
            let invalidation = request.invalidatedFrom ?? 0
            // An insertion at a token boundary can extend the preceding token.
            // Resume strictly before the edit rather than reusing that boundary.
            checkpoints.removeAll { $0.offset >= invalidation && $0.offset > 0 }
        }
        revision = request.revision
        let checkpoint = checkpoints.last(where: { $0.offset <= request.range.location })
            ?? TeakLexerCheckpoint(offset: 0, state: .normal)
        let reader = TeakUTF16Reader(snapshot: request.snapshot)
        var offset = checkpoint.offset
        var state = checkpoint.state
        var tokenStart = offset
        var spans: [TeakHighlightSpan] = []
        let upper = NSMaxRange(request.range)
        var lastCheckpoint = checkpoints.last?.offset ?? 0
        var cancellationBoundary = offset

        func checkCancellation() throws {
            guard offset >= cancellationBoundary else { return }
            try Task.checkCancellation()
            cancellationBoundary = offset + Constants.cancellationStride
        }

        func emit(_ start: Int, _ end: Int, _ scope: String) {
            let lower = max(start, request.range.location)
            let end = min(end, upper)
            if lower < end, spans.count < Constants.maximumSpans {
                spans.append(TeakHighlightSpan(range: NSRange(location: lower, length: end - lower), scope: scope))
            }
        }
        func recordCheckpoint(after position: Int, state: TeakLexerState) {
            guard position >= lastCheckpoint + Constants.checkpointStride else { return }
            checkpoints.append(TeakLexerCheckpoint(offset: position, state: state))
            lastCheckpoint = position
        }

        while offset < upper {
            try checkCancellation()
            // Every loop entry is a resumable lexer boundary, including inside
            // comments/strings (with escape state). Never checkpoint inside the
            // identifier/number loops, where resuming could invent a keyword.
            recordCheckpoint(after: offset, state: state)
            guard let unit = try reader.character(at: offset) else { break }
            let newline = unit == 10 || unit == 13 || unit == 0x2028 || unit == 0x2029
            switch state {
            case let .line(scope):
                if newline {
                    emit(tokenStart, offset, scope)
                    state = .normal
                }
                offset += 1
            case let .delimited(index, escaped, depth):
                let delimiter = delimiters[index]
                if escaped {
                    state = .delimited(index: index, escaped: false, depth: depth)
                    offset += 1
                } else if delimiter.escape == unit {
                    state = .delimited(index: index, escaped: true, depth: depth)
                    offset += 1
                } else if try reader.matches(delimiter.end, at: offset) {
                    offset += delimiter.end.count
                    if depth > 1 { state = .delimited(index: index, escaped: false, depth: depth - 1) }
                    else {
                        emit(tokenStart, offset, delimiter.scope)
                        state = .normal
                    }
                } else if delimiter.nested, try reader.matches(delimiter.start, at: offset) {
                    offset += delimiter.start.count
                    state = .delimited(index: index, escaped: false, depth: depth + 1)
                } else if newline && !delimiter.multiline {
                    emit(tokenStart, offset, delimiter.scope)
                    state = .normal
                    offset += 1
                } else {
                    offset += 1
                }
            case .normal:
                if newline {
                    offset += 1
                    continue
                }
                var found = false
                for rule in linePrefixes {
                    if try reader.matches(rule.start, at: offset), try followsIndentation(at: offset, reader: reader) {
                        tokenStart = offset
                        offset += rule.start.count
                        state = .line(scope: rule.scope)
                        found = true
                        break
                    }
                }
                if found { continue }
                for comment in lineComments {
                    if try reader.matches(comment, at: offset) {
                        tokenStart = offset
                        offset += comment.count
                        state = .line(scope: "comment")
                        found = true
                        break
                    }
                }
                if found { continue }
                for (index, delimiter) in delimiters.enumerated() {
                    if try reader.matches(delimiter.start, at: offset) {
                        if delimiter.characterLiteral {
                            guard let end = try characterLiteralEnd(at: offset, delimiter: delimiter, reader: reader) else { continue }
                            emit(offset, end, delimiter.scope)
                            offset = end
                            found = true
                            break
                        }
                        tokenStart = offset
                        offset += delimiter.start.count
                        state = .delimited(index: index, escaped: false, depth: 1)
                        found = true
                        break
                    }
                }
                if found { continue }
                if isIdentifier(unit) && !(48...57).contains(unit) {
                    let start = offset
                    var word: [UInt16] = []
                    repeat {
                        if word.count <= Constants.maximumKeywordLength { word.append(try reader.character(at: offset)!) }
                        offset += 1
                        try checkCancellation()
                        if offset >= upper { break }
                        let next = try reader.character(at: offset)
                        if !isIdentifierContinuation(next) { break }
                    } while true
                    if word.count <= Constants.maximumKeywordLength,
                       !isIdentifierContinuation(try reader.character(at: offset)) {
                        let value = String(decoding: word, as: UTF16.self)
                        let keyword = language.caseInsensitiveKeywords == true ? value.lowercased() : value
                        if let scope = try identifierScope(word: word, start: start, end: offset, reader: reader)
                            ?? keywords[keyword] { emit(start, offset, scope) }
                    }
                } else if language.highlightsNumbers && (48...57).contains(unit) {
                    let start = offset
                    repeat {
                        offset += 1
                        try checkCancellation()
                        if offset >= upper { break }
                        let next = try reader.character(at: offset)
                        if !isNumberContinuation(next) { break }
                    } while true
                    emit(start, offset, "number")
                } else { offset += 1 }
            }
        }
        switch state {
        case let .line(scope): emit(tokenStart, offset, scope)
        case let .delimited(index, _, _): emit(tokenStart, offset, delimiters[index].scope)
        case .normal: break
        }
        try Task.checkCancellation()
        return spans
    }

    private func isIdentifier(_ value: UInt16?) -> Bool {
        guard let value else { return false }
        return (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value)
            || value == 95 || value == 36 || value >= 128 && value != 0x2028 && value != 0x2029
    }

    private func isIdentifierContinuation(_ value: UInt16?) -> Bool {
        isIdentifier(value) || value.map { identifierCharacters.contains($0) } == true
    }

    private func followsIndentation(at offset: Int, reader: TeakUTF16Reader) throws -> Bool {
        var cursor = offset
        while cursor > 0 {
            cursor -= 1
            if cursor % Constants.cancellationStride == 0 { try Task.checkCancellation() }
            guard let unit = try reader.character(at: cursor) else { return false }
            if unit == 10 || unit == 13 || unit == 0x2028 || unit == 0x2029 { return true }
            if unit != 32 && unit != 9 { return false }
        }
        return true
    }

    private func identifierScope(word: [UInt16], start: Int, end: Int, reader: TeakUTF16Reader) throws -> String? {
        for rule in identifierRules {
            if !rule.startsWith.isEmpty && !rule.startsWith.contains(where: { word.starts(with: $0) }) { continue }
            if !rule.precededBy.isEmpty {
                var matches = false
                for prefix in rule.precededBy where start >= prefix.count {
                    if try reader.matches(prefix, at: start - prefix.count) { matches = true; break }
                }
                if !matches { continue }
            }
            if !rule.followedBy.isEmpty {
                var cursor = end
                while cursor < end + Constants.maximumContextWhitespace,
                      let unit = try reader.character(at: cursor), unit == 32 || unit == 9 { cursor += 1 }
                var matches = false
                for suffix in rule.followedBy {
                    if try reader.matches(suffix, at: cursor) { matches = true; break }
                }
                if !matches { continue }
            }
            return rule.scope
        }
        return nil
    }

    /// Character literals consume one scalar or a bounded escape. In Rust,
    /// an apostrophe before a lifetime must leave the following code in normal state.
    private func characterLiteralEnd(at offset: Int, delimiter: TeakCompiledDelimiter,
                                     reader: TeakUTF16Reader) throws -> Int? {
        var cursor = offset + delimiter.start.count
        guard let unit = try reader.character(at: cursor), unit != 10, unit != 13, unit != 39 else { return nil }
        if unit == delimiter.escape {
            cursor += 1
            guard let escape = try reader.character(at: cursor), escape != 10, escape != 13 else { return nil }
            cursor += 1
            if escape == 117, try reader.character(at: cursor) == 123 {
                cursor += 1
                let start = cursor
                while cursor - start < 12, let next = try reader.character(at: cursor), isHex(next) || next == 95 { cursor += 1 }
                guard cursor > start, try reader.character(at: cursor) == 125 else { return nil }
                cursor += 1
            } else if escape == 117 || escape == 85 {
                for _ in 0..<(escape == 117 ? 4 : 8) {
                    guard let next = try reader.character(at: cursor), isHex(next) else { return nil }
                    cursor += 1
                }
            } else if escape == 120 {
                let start = cursor
                while cursor - start < 8, let next = try reader.character(at: cursor), isHex(next) { cursor += 1 }
                if cursor == start { return nil }
            } else if (48...55).contains(escape) {
                for _ in 0..<2 {
                    guard let next = try reader.character(at: cursor), (48...55).contains(next) else { break }
                    cursor += 1
                }
            }
        } else {
            cursor += 1
            if (0xD800...0xDBFF).contains(unit), let next = try reader.character(at: cursor),
               (0xDC00...0xDFFF).contains(next) { cursor += 1 }
        }
        return try reader.matches(delimiter.end, at: cursor) ? cursor + delimiter.end.count : nil
    }

    private func isHex(_ unit: UInt16) -> Bool {
        (48...57).contains(unit) || (65...70).contains(unit) || (97...102).contains(unit)
    }

    private func isNumberContinuation(_ value: UInt16?) -> Bool {
        guard let value else { return false }
        return (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
            || value == 46 || value == 95 || value == 120 || value == 88 || value == 110
    }
}

private extension TeakRuleHighlighter {
    enum Constants {
        static let maximumSpans = 4096
        static let checkpointStride = 8192
        static let cancellationStride = 1024
        static let maximumKeywordLength = 128
        static let maximumContextWhitespace = 256
    }
}
