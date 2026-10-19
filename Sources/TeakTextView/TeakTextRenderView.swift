#if canImport(UIKit)
import UIKit
@_spi(Rendering) import TeakTextCore

/// A non-drawing container of document-anchored tiles. Scrolling moves their
/// existing rasters; only newly exposed or explicitly invalidated tiles redraw.
@MainActor
final class TeakTextRenderView: UIView {
    weak var textView: UITextView?
    private var tiles: [Int: TeakTextTileView] = [:]
    private var recycledTiles: [TeakTextTileView] = []
    private var layoutWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func invalidateAll() {
        for tile in tiles.values {
            tile.prepareForReuse()
            recycledTiles.append(tile)
        }
        tiles.removeAll(keepingCapacity: true)
    }

    func resetDocument() {
        invalidateAll()
        // A new document has no pixels or line objects in common with this
        // one. Release the views/backing stores as well as their source rows.
        recycledTiles.removeAll()
    }

    func invalidate(_ changes: [TeakHighlightChange]) {
        guard !changes.isEmpty else { return }
        for tile in tiles.values { tile.invalidate(changes) }
    }

    func updateViewport() {
        guard let textView, let layout = textView.textLayoutManager,
              let viewport = layout.textViewportLayoutController.viewportRange,
              let content = layout.textContentManager else { return }
        let visible = textView.bounds
        guard visible.width > 0, visible.height > 0 else { return }
        if layoutWidth != visible.width {
            invalidateAll()
            layoutWidth = visible.width
        }
        // This container has no draw override and therefore no document-sized
        // backing bitmap. Its children each have a fixed, bounded drawing area.
        let containerFrame = CGRect(x: 0, y: 0, width: visible.width,
            height: max(visible.height, textView.contentSize.height))
        if frame != containerFrame { frame = containerFrame }

        let prefetch = visible.height / 2
        let lower = max(0, visible.minY - prefetch)
        let upper = max(lower, visible.maxY + prefetch)
        let first = Int(floor(lower / Constants.tileHeight))
        let last = Int(floor(upper / Constants.tileHeight))
        for index in Array(tiles.keys) where index < first || index > last {
            if let tile = tiles.removeValue(forKey: index) {
                tile.prepareForReuse()
                recycledTiles.append(tile)
            }
        }

        var rowsByTile: [Int: [TeakTextRenderRow]] = [:]
        let inset = textView.textContainerInset
        let documentLength = textView.textStorage.length
        let band = CGRect(x: 0, y: CGFloat(first) * Constants.tileHeight,
            width: visible.width, height: CGFloat(last - first + 1) * Constants.tileHeight)
        layout.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.state == .layoutAvailable else { return false }
            let origin = CGPoint(x: inset.left + fragment.layoutFragmentFrame.minX,
                                 y: inset.top + fragment.layoutFragmentFrame.minY)
            if origin.y > band.maxY { return false }
            if let fragment = fragment as? TeakTextLayoutFragment, fragment.usesViewportRendering,
               let elementRange = fragment.textElement?.elementRange {
                let elementOffset = content.offset(from: content.documentRange.location, to: elementRange.location)
                guard elementOffset >= 0, elementOffset <= documentLength else { return false }
                let lines = fragment.textLineFragments
                var lower = 0
                var upper = lines.count
                while lower < upper {
                    let middle = lower + (upper - lower) / 2
                    if origin.y + lines[middle].typographicBounds.maxY < band.minY { lower = middle + 1 }
                    else { upper = middle }
                }
                // Include adjacent rows so ink extending beyond typographic bounds
                // is also available at tile seams. Each tile clips its own raster.
                var index = max(0, lower - 1)
                while index < lines.count {
                    let line = lines[index]
                    let rowBounds = line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y)
                    let padding = line.typographicBounds.height
                    if rowBounds.minY - padding > band.maxY { break }
                    let characterRange = line.characterRange
                    guard characterRange.location >= 0, characterRange.length >= 0,
                          characterRange.location <= documentLength - elementOffset,
                          characterRange.length <= documentLength - elementOffset - characterRange.location else {
                        index += 1
                        continue
                    }
                    let rowFirst = max(first, Int(floor((rowBounds.minY - padding) / Constants.tileHeight)))
                    let rowLast = min(last, Int(floor((rowBounds.maxY + padding) / Constants.tileHeight)))
                    let range = NSRange(location: elementOffset + characterRange.location,
                                        length: characterRange.length)
                    if rowFirst <= rowLast {
                        for tileIndex in rowFirst...rowLast {
                            rowsByTile[tileIndex, default: []].append(TeakTextRenderRow(line: line,
                                origin: CGPoint(x: rowBounds.minX,
                                    y: rowBounds.minY - CGFloat(tileIndex) * Constants.tileHeight), range: range))
                        }
                    }
                    index += 1
                }
            }
            return origin.y + fragment.layoutFragmentFrame.height < band.maxY
        }

        for index in first...last {
            guard let rows = rowsByTile[index], !rows.isEmpty else {
                if let tile = tiles.removeValue(forKey: index) {
                    tile.prepareForReuse()
                    recycledTiles.append(tile)
                }
                continue
            }
            let tile: TeakTextTileView
            if let existing = tiles[index] { tile = existing }
            else {
                tile = recycledTiles.popLast() ?? TeakTextTileView(frame: .zero)
                tiles[index] = tile
                addSubview(tile)
            }
            let tileFrame = CGRect(x: 0, y: CGFloat(index) * Constants.tileHeight,
                                   width: visible.width, height: Constants.tileHeight)
            if tile.frame != tileFrame { tile.frame = tileFrame }
            tile.configure(rows: rows)
        }
        let maximumRecycled = last - first + 1
        if recycledTiles.count > maximumRecycled {
            recycledTiles.removeLast(recycledTiles.count - maximumRecycled)
        }
    }
}

private extension TeakTextRenderView {
    enum Constants {
        static let tileHeight: CGFloat = 256
    }
}
#endif
