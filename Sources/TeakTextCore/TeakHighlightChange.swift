import Foundation

/// A presentation change. A nil scope restores the document's foreground color.
@_spi(Rendering)
public struct TeakHighlightChange: Sendable {
    public let range: NSRange
    public let scope: String?
}
