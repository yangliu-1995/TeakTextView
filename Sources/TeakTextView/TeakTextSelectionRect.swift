#if canImport(UIKit)
import UIKit

/// Keeps native geometry and bidi information, but reports only real selection
/// endpoints when the display query has been clipped to the current viewport.
@MainActor
final class TeakTextSelectionRect: UITextSelectionRect {
    private let source: UITextSelectionRect
    private let includesStart: Bool
    private let includesEnd: Bool

    init(source: UITextSelectionRect, containsStart: Bool, containsEnd: Bool) {
        self.source = source
        includesStart = containsStart
        includesEnd = containsEnd
        super.init()
    }

    override var rect: CGRect { source.rect }
    override var writingDirection: NSWritingDirection { source.writingDirection }
    override var containsStart: Bool { includesStart && source.containsStart }
    override var containsEnd: Bool { includesEnd && source.containsEnd }
    override var isVertical: Bool { source.isVertical }

    @available(iOS 17.4, *)
    override var transform: CGAffineTransform { source.transform }
}
#endif
