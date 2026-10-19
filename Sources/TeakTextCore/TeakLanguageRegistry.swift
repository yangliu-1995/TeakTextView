import Foundation

/// A host can download a JSON rule pack, then import its local URL here.
public actor TeakLanguageRegistry {
    private var bundled: [TeakLanguageDefinition]?
    public init() {}

    public func makeHighlighter(language: TeakLanguageDefinition) throws -> TeakRuleHighlighter {
        try TeakRuleHighlighter(language: language)
    }

    public func bundledJavaScript() throws -> TeakLanguageDefinition {
        try bundledLanguage(id: "javascript")
    }

    public func bundledLanguage(id: String) throws -> TeakLanguageDefinition {
        guard let language = try bundledLanguages().first(where: { $0.id == id }) else {
            throw TeakTextError.invalidLanguageDefinition("Unknown bundled language: \(id)")
        }
        return language
    }

    public func bundledLanguages() throws -> [TeakLanguageDefinition] {
        if let bundled { return bundled }
        let definitions = try Constants.bundledIDs.map { id in
            guard let url = Bundle.module.url(forResource: id, withExtension: "json") else {
                throw TeakTextError.invalidLanguageDefinition("Missing bundled language: \(id)")
            }
            let definition = try load(url: url)
            guard definition.id == id else {
                throw TeakTextError.invalidLanguageDefinition("Bundled language identifier mismatch: \(id)")
            }
            return definition
        }
        bundled = definitions
        return definitions
    }

    /// Longest suffix wins, so compound suffixes such as d.ts remain explicit.
    /// An unknown filename stays plain text; only known interpreter shebangs
    /// provide a fallback for executable scripts without a recognized suffix.
    public nonisolated static func detect(fileName: String?, firstLine: String = "",
                                         among definitions: [TeakLanguageDefinition]) -> TeakLanguageDefinition? {
        if let name = fileName?.lowercased() {
            if let exact = definitions.first(where: { ($0.fileNames ?? []).contains { $0.lowercased() == name } }) {
                return exact
            }
            var match: TeakLanguageDefinition?
            var length = 0
            for definition in definitions {
                for suffix in definition.fileExtensions {
                    let suffix = suffix.lowercased()
                    if name.hasSuffix("." + suffix), suffix.count > length {
                        match = definition
                        length = suffix.count
                    }
                }
            }
            if let match { return match }
        }
        guard firstLine.hasPrefix("#!") else { return nil }
        let line = firstLine.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first ?? ""
        let commands = line.dropFirst(2).split(whereSeparator: \.isWhitespace)
        guard let executable = commands.first else { return nil }
        let name = executable.split(separator: "/").last ?? executable
        let interpreter: Substring?
        if name == "env" {
            interpreter = commands.dropFirst().first { !$0.hasPrefix("-") && !$0.contains("=") }
        } else { interpreter = name }
        guard let interpreter else { return nil }
        let command = interpreter.split(separator: "/").last ?? interpreter
        if command == "python" || command.hasPrefix("python")
            && command.dropFirst(6).allSatisfy({ $0.isNumber || $0 == "." }) {
            return definitions.first { $0.id == "python" }
        }
        if command == "bash" || command == "sh" || command == "zsh" {
            return definitions.first { $0.id == "bash" }
        }
        return nil
    }

    public func load(url: URL) throws -> TeakLanguageDefinition {
        guard url.isFileURL else { throw TeakTextError.localFileRequired }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Constants.maximumBytes + 1) ?? Data()
        guard data.count <= Constants.maximumBytes else {
            throw TeakTextError.invalidLanguageDefinition("Language definition exceeds 1 MiB")
        }
        let definition = try JSONDecoder().decode(TeakLanguageDefinition.self, from: data)
        try definition.validate()
        return definition
    }
}

private extension TeakLanguageRegistry {
    enum Constants {
        static let maximumBytes = 1_048_576
        static let bundledIDs = ["javascript", "typescript", "python", "html", "css", "markdown",
                                 "java", "csharp", "c", "cpp", "go", "rust", "swift", "kotlin",
                                 "sql", "bash", "json", "yaml", "toml"]
    }
}
