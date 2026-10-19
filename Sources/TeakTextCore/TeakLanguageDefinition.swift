import Foundation

/// A deliberately finite lexical grammar, not executable code or unrestricted regex.
public struct TeakLanguageDefinition: Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let displayName: String
    public let fileExtensions: [String]
    public let keywords: [String: [String]]
    public let lineComments: [String]
    public let blockComments: [TeakDelimitedRule]
    public let strings: [TeakDelimitedRule]
    public let highlightsNumbers: Bool
    public let fileNames: [String]?
    public let caseInsensitiveKeywords: Bool?
    public let identifierCharacters: String?
    public let identifierRules: [TeakIdentifierRule]?
    public let linePrefixes: [TeakLinePrefixRule]?

    public func validate() throws {
        guard schemaVersion == 1, !id.isEmpty, id.utf8.count <= 128,
              fileExtensions.count <= 64, keywords.count <= 32,
              keywords.values.reduce(0, { $0 + $1.count }) <= 50_000,
              lineComments.count <= 16, blockComments.count <= 16, strings.count <= 16,
              (fileNames?.count ?? 0) <= 64, (identifierCharacters?.utf16.count ?? 0) <= 32,
              (identifierRules?.count ?? 0) <= 32, (linePrefixes?.count ?? 0) <= 16 else {
            throw TeakTextError.invalidLanguageDefinition("Unsupported schema or grammar limits")
        }
        let delimiters = lineComments + (blockComments + strings).flatMap { [$0.start, $0.end] }
        guard delimiters.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 64 }),
              keywords.values.joined().allSatisfy({ !$0.isEmpty && $0.utf16.count <= 128 }),
              (blockComments + strings).allSatisfy({ ($0.escape?.utf16.count ?? 0) <= 1 }) else {
            throw TeakTextError.invalidLanguageDefinition("Invalid delimiter, escape or keyword")
        }
        for rule in blockComments + strings {
            guard rule.nested != true || rule.multiline && rule.start != rule.end,
                  rule.characterLiteral != true || rule.start == "'" && rule.end == "'" && !rule.multiline else {
                throw TeakTextError.invalidLanguageDefinition("Invalid nested or character delimiter")
            }
        }
        for rule in identifierRules ?? [] {
            let contexts = [rule.precededBy ?? [], rule.followedBy ?? [], rule.startsWith ?? []]
            guard contexts.contains(where: { !$0.isEmpty }), contexts.allSatisfy({ $0.count <= 16 }),
                  contexts.joined().allSatisfy({ !$0.isEmpty && $0.utf16.count <= 64 }),
                  !rule.scope.isEmpty, rule.scope.utf16.count <= 64 else {
                throw TeakTextError.invalidLanguageDefinition("Invalid identifier context")
            }
        }
        guard (linePrefixes ?? []).allSatisfy({
            !$0.start.isEmpty && $0.start.utf16.count <= 64 && !$0.scope.isEmpty
                && $0.scope.utf16.count <= 64 && $0.start.first?.isWhitespace == false
        }) else { throw TeakTextError.invalidLanguageDefinition("Invalid line prefix") }
    }
}
