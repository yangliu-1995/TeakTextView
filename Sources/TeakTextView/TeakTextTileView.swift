#if canImport(UIKit)
import UIKit
@_spi(Rendering) import TeakTextCore

/// Retains its raster while scrolling. Only source/geometry or color changes
/// invalidate drawing; a new TextKit object alone does not change its pixels.
@MainActor
final class TeakTextTileView: UIView {
    private var rows: [TeakTextRenderRow] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self,
                                 UITraitDisplayScale.self]) { (view: TeakTextTileView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func configure(rows newRows: [TeakTextRenderRow]) {
        // The editor clears tiles on document edits and width changes. Within
        // that boundary identical UTF-16 ranges and positions retain their glyphs;
        // foreground changes are explicitly invalidated by the highlight commit.
        let changed = rows.count != newRows.count || zip(rows, newRows).contains {
            $0.range != $1.range || $0.origin != $1.origin
        }
        rows = newRows
        if changed { setNeedsDisplay() }
    }

    func invalidate(_ changes: [TeakHighlightChange]) {
        guard let first = rows.first, let last = rows.last else { return }
        let coveredRange = NSUnionRange(first.range, last.range)
        guard changes.contains(where: { NSIntersectionRange(coveredRange, $0.range).length > 0 }) else { return }
        setNeedsDisplay()
    }

    func prepareForReuse() {
        rows.removeAll(keepingCapacity: true)
        removeFromSuperview()
        // Reconfiguration always redraws this tile. Its previous raster has
        // no reuse value and can otherwise survive in the offscreen view pool.
        layer.contents = nil
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for row in rows { row.line.draw(at: row.origin, in: context) }
    }
}
#endif
