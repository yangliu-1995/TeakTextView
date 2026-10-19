#if canImport(UIKit)
import Foundation

public struct TeakEditorMetrics {
    public let utf16Count: Int
    public let lineCount: Int
    public let chunkCount: Int
    public let revision: UInt64
    public let isDirty: Bool
    public let isLoading: Bool
    public let isHighlighting: Bool
    public let highlightedTokenCount: Int
    public let lastHighlightMilliseconds: Double
}
#endif
