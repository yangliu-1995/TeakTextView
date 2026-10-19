import Foundation

public struct TeakDelimitedRule: Codable, Sendable {
    public let start: String
    public let end: String
    public let escape: String?
    public let multiline: Bool
    public let scope: String
    public let nested: Bool?
    public let characterLiteral: Bool?
}
