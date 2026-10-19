#if canImport(UIKit)
import UIKit

@MainActor
final class TeakInputTextView: UITextView {
    var onDidLayout: (() -> Void)?
    private var selectionViewportRange: NSRange?
    private var selectionViewportBounds = CGRect.null

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        // Touch admission otherwise bypasses UITextInput.selectionRects and
        // enumerates the whole selection before the scroll gesture can begin.
        // Decline that optional capability only for our large selection. UIKit
        // then uses its existing segment-based hit test with the native targets.
        if let aSelector, Thread.isMainThread,
           TeakTextTouchSupport.prefersSelectionSegments(for: aSelector),
           MainActor.assumeIsolated({ selectedRange.length > Constants.maximumNativeGeometryLength }) {
            return false
        }
        return super.responds(to: aSelector)
    }

    override func firstRect(for range: UITextRange) -> CGRect {
        // UITextInput asks for the FIRST line, not the geometry of every line
        // in the range. UIKit's large-range implementation lays out the entire
        // document before returning that first rectangle.
        guard offset(from: range.start, to: range.end) > Constants.maximumNativeGeometryLength,
              let line = tokenizer.rangeEnclosingPosition(range.start, with: .line,
                  inDirection: UITextDirection.storage(.forward)),
              compare(line.start, to: range.start) != .orderedDescending,
              compare(line.end, to: range.start) == .orderedDescending else {
            return super.firstRect(for: range)
        }
        let end = compare(line.end, to: range.end) == .orderedDescending ? range.end : line.end
        guard let firstLine = textRange(from: range.start, to: end) else {
            return super.firstRect(for: range)
        }
        return super.firstRect(for: firstLine)
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let start = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        let requested = NSRange(location: start, length: length)
        // Virtualize the current selection's display, not arbitrary geometry
        // requests made by other UITextInput clients. UIKit's selection display
        // otherwise materializes all rectangles just to discard offscreen ones.
        guard length > Constants.maximumNativeGeometryLength, requested == selectedRange else {
            return super.selectionRects(for: range)
        }
        // UIKit can ask while its canvas is publishing a new viewport, when
        // viewportRange is temporarily nil. There is no current display geometry
        // then. Do not force whole-document layout from inside that layout pass;
        // updateSelectionViewport requests a refresh after native layout settles.
        guard let viewport = selectionViewport() else { return [] }
        let visible = NSIntersectionRange(requested, viewport)
        guard visible.length > 0,
              let lower = position(from: beginningOfDocument, offset: visible.location),
              let upper = position(from: lower, offset: visible.length),
              let clipped = textRange(from: lower, to: upper) else { return [] }
        let containsStart = visible.location == requested.location
        let containsEnd = NSMaxRange(visible) == NSMaxRange(requested)
        return super.selectionRects(for: clipped).map {
            // Clipping must never create a draggable handle at a viewport edge.
            TeakTextSelectionRect(source: $0, containsStart: containsStart, containsEnd: containsEnd)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Decline auxiliary commands before calling UIKit. In the device trace,
        // validating the speech menu eagerly tagged the entire selected document.
        // Use public editing selectors so this also rejects future auxiliary items.
        guard Constants.editingActions.contains(action) else { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    func editingMenu() -> UIMenu {
        let commands = [
            UICommand(title: String(localized: "Cut"), action: #selector(cut(_:))),
            UICommand(title: String(localized: "Copy"), action: #selector(copy(_:))),
            UICommand(title: String(localized: "Paste"), action: #selector(paste(_:))),
            UICommand(title: String(localized: "Select"), action: #selector(select(_:))),
            UICommand(title: String(localized: "Select All"), action: #selector(selectAll(_:))),
            UICommand(title: String(localized: "Delete"), action: #selector(delete(_:)))
        ]
        return UIMenu(children: commands.filter { canPerformAction($0.action, withSender: nil) })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectionViewport()
        // The wrapper lays out before its native input subview. Notify only after
        // UITextView has had its own layout pass, when its viewport can be queried.
        onDidLayout?()
    }

    private func selectionViewport() -> NSRange? {
        guard let layout = textLayoutManager, let content = layout.textContentManager,
              let viewport = layout.textViewportLayoutController.viewportRange else { return nil }
        let start = content.offset(from: content.documentRange.location, to: viewport.location)
        let end = content.offset(from: content.documentRange.location, to: viewport.endLocation)
        guard start >= 0, end >= start, end <= textStorage.length else { return nil }
        // The viewport includes whole bounded layout elements and overscan, so
        // clipping boundaries lie outside the visible text wherever possible.
        return NSRange(location: start, length: end - start)
    }

    private func updateSelectionViewport() {
        guard selectedRange.length > Constants.maximumNativeGeometryLength else {
            selectionViewportRange = nil
            selectionViewportBounds = .null
            return
        }
        let viewport = selectionViewport()
        guard viewport != selectionViewportRange || bounds != selectionViewportBounds else { return }
        selectionViewportRange = viewport
        selectionViewportBounds = bounds
        // Refresh after native viewport layout, including scrolling and width
        // changes. The key above prevents a selection/layout invalidation loop.
        for case let interaction as UITextSelectionDisplayInteraction in interactions {
            interaction.setNeedsSelectionUpdate()
        }
    }
}

private extension TeakInputTextView {
    enum Constants {
        static let maximumNativeGeometryLength = 4096
        static let editingActions: Set<Selector> = [
            #selector(cut(_:)), #selector(copy(_:)), #selector(paste(_:)),
            #selector(pasteAndMatchStyle(_:)), #selector(select(_:)),
            #selector(selectAll(_:)), #selector(delete(_:))
        ]
    }
}
#endif
