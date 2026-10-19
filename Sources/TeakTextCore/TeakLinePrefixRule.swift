import Foundation

/// Colors the remainder of a line when this prefix follows only indentation.
public struct TeakLinePrefixRule: Codable, Sendable {
    public let start: String
    public let scope: String
}
