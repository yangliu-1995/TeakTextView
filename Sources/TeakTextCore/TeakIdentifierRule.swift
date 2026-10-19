import Foundation

/// Finite context tests for tag names, properties, attributes and variables.
/// Provided conditions are combined; alternatives within each list use OR.
public struct TeakIdentifierRule: Codable, Sendable {
    public let precededBy: [String]?
    public let followedBy: [String]?
    public let startsWith: [String]?
    public let scope: String
}
