import Foundation

/// Implementations should use an actor for parsing. No UIKit objects cross this boundary.
public protocol TeakTextPlugin: Sendable {
    var id: String { get }
    func highlights(for request: TeakHighlightRequest) async throws -> [TeakHighlightSpan]
}
