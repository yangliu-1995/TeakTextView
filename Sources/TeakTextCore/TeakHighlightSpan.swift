import Foundation

public struct TeakHighlightSpan: Sendable {
    public let range: NSRange
    public let scope: String

    public init(range: NSRange, scope: String) {
        self.range = range
        self.scope = scope
    }
}
