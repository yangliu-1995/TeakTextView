import Foundation
import Testing
@testable import TeakTextCore

struct TeakTextCoreTests {
    @Test func logicalLineNumbersFollowNewlinesAcrossChunksAndEdits() async throws {
        let io = TeakDocumentIO()
        let document = try await io.prepare(text: "a\r\nb\rc\nd\u{2028}e\u{2029}")
        let ranks = [1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6]
        let starts: Set<Int> = [0, 3, 5, 7, 9, 11]
        for (offset, expected) in ranks.enumerated() {
            #expect(try document.lineNumber(atUTF16Offset: offset) == expected)
            #expect(try document.isLineStart(atUTF16Offset: offset) == starts.contains(offset))
        }
        let empty = try await io.prepare(text: "")
        #expect(try empty.lineNumber(atUTF16Offset: 0) == 1)
        #expect(try empty.isLineStart(atUTF16Offset: 0))
        let splitCRLF = try await io.prepare(text: String(repeating: "x", count: 8191) + "\r\n\rZ\n")
        #expect(try splitCRLF.lineNumber(atUTF16Offset: 8192) == 1)
        #expect(try !splitCRLF.isLineStart(atUTF16Offset: 8192))
        #expect(try splitCRLF.lineNumber(atUTF16Offset: 8193) == 2)
        #expect(try splitCRLF.lineNumber(atUTF16Offset: 8194) == 3)
        #expect(try splitCRLF.lineNumber(atUTF16Offset: splitCRLF.utf16Count) == 4)
        let edited = try splitCRLF.replacing(NSRange(location: 8192, length: 1), with: "")
        #expect(try edited.lineNumber(atUTF16Offset: 8192) == 2)
        #expect(try edited.isLineStart(atUTF16Offset: 8192))
        #expect(try edited.lineNumber(atUTF16Offset: 8193) == 3)
        let prepended = try edited.replacing(NSRange(location: 0, length: 0), with: "\n")
        #expect(try prepended.lineNumber(atUTF16Offset: 8194) == 4)
        #expect(try splitCRLF.lineNumber(atUTF16Offset: 8192) == 1)
    }

    @Test func jQueryJavaScriptOpensHighlightsAndSaves() async throws {
        let source = try #require(Bundle.module.url(forResource: "jquery",
            withExtension: "js", subdirectory: "Fixtures"))
        let io = TeakDocumentIO()
        let snapshot = try await io.open(url: source)
        #expect(snapshot.lineCount >= 9000)
        let registry = TeakLanguageRegistry()
        let plugin = try await registry.makeHighlighter(language: registry.bundledJavaScript())
        let result = try await plugin.highlights(for: TeakHighlightRequest(documentID: UUID(), revision: 0,
            snapshot: snapshot, range: NSRange(location: 0, length: min(16_384, snapshot.utf16Count)), invalidatedFrom: 0))
        #expect(!result.isEmpty)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".js")
        defer { try? FileManager.default.removeItem(at: output) }
        try await io.save(snapshot, to: output)
        #expect(try Data(contentsOf: source) == Data(contentsOf: output))
    }

    @Test func editsMatchFoundationAndPreserveSnapshots() async throws {
        let io = TeakDocumentIO()
        var expected = String(repeating: "const a = 1;\r\n", count: 1700)
        var document = try await io.prepare(text: expected)
        let original = document
        var seed: UInt64 = 42
        func random(_ upper: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1
            return Int((seed >> 32) % UInt64(max(upper, 1)))
        }
        let insertions = ["", "x", "中文😃", "\r", "\n", "\r\n", "\u{2028}"]
        for _ in 0..<400 {
            let string = expected as NSString
            let offset = random(string.length + 1)
            let length = min(random(30), string.length - offset)
            let range = string.rangeOfComposedCharacterSequences(for: NSRange(location: offset, length: length))
            let text = insertions[random(insertions.count)]
            expected = string.replacingCharacters(in: range, with: text)
            document = try document.replacing(range, with: text)
            #expect(try document.text(in: NSRange(location: 0, length: document.utf16Count)) == expected)
            let normalized = expected.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\u{2028}", with: "\n")
            #expect(document.lineCount == normalized.filter { $0 == "\n" }.count + 1)
        }
        #expect(original.utf16Count == 1700 * 14)
        #expect(try original.text(in: NSRange(location: 0, length: 14)) == "const a = 1;\r\n")
    }

    @Test func streamedFileRoundTripsEncodingAndUnicodeBoundaries() async throws {
        let io = TeakDocumentIO()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = String(repeating: "a", count: 65_532) + "中文😃\r\n" + String(repeating: "z\n", count: 20_000)
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            let source = directory.appendingPathComponent("source.txt")
            let output = directory.appendingPathComponent("output.txt")
            let marker: [UInt8] = encoding == .utf8 ? [0xEF, 0xBB, 0xBF]
                : encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]
            var data = Data(marker)
            data.append(try #require(text.data(using: encoding)))
            try data.write(to: source)
            let document = try await io.open(url: source)
            #expect(document.encoding == encoding)
            #expect(document.hasByteOrderMark)
            try await io.save(document, to: output)
            #expect(try Data(contentsOf: output) == data)
        }
    }

    @Test func typingCoalescesChunks() async throws {
        let io = TeakDocumentIO()
        var document = try await io.prepare(text: "")
        for _ in 0..<1000 {
            document = try document.replacing(NSRange(location: document.utf16Count, length: 0), with: "x")
        }
        #expect(document.chunkCount <= 2)
        #expect(document.utf16Count == 1000)
    }

    @Test func highlightingRetainsMultilineContextAndInvalidatesEdits() async throws {
        let registry = TeakLanguageRegistry()
        let language = try await registry.bundledJavaScript()
        let plugin = try await registry.makeHighlighter(language: language)
        let io = TeakDocumentIO()
        let text = "/*\n" + String(repeating: "comment line\n", count: 1700) + "*/\nconst value = 42;"
        let document = try await io.prepare(text: text)
        let offset = (text as NSString).range(of: "comment line", options: .backwards).location
        let id = UUID()
        let request = TeakHighlightRequest(documentID: id, revision: 0, snapshot: document,
            range: NSRange(location: offset, length: document.utf16Count - offset), invalidatedFrom: 0)
        let result = try await plugin.highlights(for: request)
        #expect(result.first?.scope == "comment")
        #expect(result.contains { $0.scope == "keyword" })
        let edited = try document.replacing(NSRange(location: 0, length: 2), with: "  ")
        let next = TeakHighlightRequest(documentID: id, revision: 1, snapshot: edited,
            range: request.range, invalidatedFrom: 0)
        let changed = try await plugin.highlights(for: next)
        #expect(!changed.contains { $0.scope == "comment" })
    }
}
