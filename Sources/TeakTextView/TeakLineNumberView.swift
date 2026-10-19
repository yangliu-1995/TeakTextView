#if canImport(UIKit)
import UIKit
import TeakTextCore

/// A fixed gutter that draws only already-laid-out, visible logical line starts.
@MainActor
final class TeakLineNumberView: UIView {
    weak var textView: UITextView?
    var document: TeakDocumentSnapshot?
    var font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
    var foregroundColor = UIColor.secondaryLabel

    var preferredWidth: CGFloat {
        let digits = max(Constants.minimumDigits, String(document?.lineCount ?? 1).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        return ceil(CGFloat(digits) * digitWidth + Constants.horizontalPadding * 2 + Constants.separatorWidth)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        UIColor.separator.setFill()
        UIRectFill(CGRect(x: bounds.maxX - Constants.separatorWidth, y: bounds.minY,
                          width: Constants.separatorWidth, height: bounds.height))
        guard let textView, let document, let layout = textView.textLayoutManager,
              let manager = layout.textContentManager else { return }
        let viewport = layout.textViewportLayoutController.viewportRange
        var lastDrawnOffset: Int?
        if let viewport {
            layout.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
                guard fragment.state == .layoutAvailable else { return false }
                let origin = textView.convert(CGPoint(x: 0,
                    y: textView.textContainerInset.top + fragment.layoutFragmentFrame.minY), to: self)
                if origin.y > self.bounds.maxY { return false }
                guard let elementRange = fragment.textElement?.elementRange else { return true }
                let elementOffset = manager.offset(from: manager.documentRange.location, to: elementRange.location)
                guard elementOffset >= 0, elementOffset <= document.utf16Count else { return true }
                let lines = fragment.textLineFragments
                // A single wrapped paragraph can contain thousands of visual rows.
                // Binary-search into its visible rows instead of walking from its start.
                var lower = 0
                var upper = lines.count
                while lower < upper {
                    let middle = lower + (upper - lower) / 2
                    if origin.y + lines[middle].typographicBounds.maxY < self.bounds.minY { lower = middle + 1 }
                    else { upper = middle }
                }
                var index = lower
                while index < lines.count {
                    let line = lines[index]
                    let top = origin.y + line.typographicBounds.minY
                    if top > self.bounds.maxY { break }
                    let relativeOffset = line.characterRange.location
                    if relativeOffset >= 0, relativeOffset <= document.utf16Count - elementOffset {
                        let offset = elementOffset + relativeOffset
                        if offset != lastDrawnOffset,
                           (try? document.isLineStart(atUTF16Offset: offset)) == true,
                           let number = try? document.lineNumber(atUTF16Offset: offset) {
                            self.drawNumber(number, baseline: top + line.glyphOrigin.y)
                            lastDrawnOffset = offset
                        }
                    }
                    index += 1
                }
                return origin.y + fragment.layoutFragmentFrame.height < self.bounds.maxY
            }
        }
        // UITextView may keep its terminal empty row outside the normal fragments.
        // Query its native caret geometry only when the document end is in the viewport.
        let end = document.utf16Count
        let endIsVisible = document.utf16Count == 0 || viewport.map {
            manager.offset(from: manager.documentRange.location, to: $0.endLocation) == end
        } == true
        if endIsVisible, lastDrawnOffset != end,
           (try? document.isLineStart(atUTF16Offset: end)) == true {
            let caret = textView.convert(textView.caretRect(for: textView.endOfDocument), to: self)
            if caret.height > 0, caret.maxY >= bounds.minY, caret.minY <= bounds.maxY {
                drawNumber(document.lineCount, baseline: caret.midY - font.lineHeight / 2 + font.ascender)
            }
        }
    }

    private func drawNumber(_ number: Int, baseline: CGFloat) {
        let string = String(number) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foregroundColor]
        let width = string.size(withAttributes: attributes).width
        string.draw(at: CGPoint(x: bounds.maxX - Constants.horizontalPadding - Constants.separatorWidth - width,
                                y: baseline - font.ascender), withAttributes: attributes)
    }
}

private extension TeakLineNumberView {
    enum Constants {
        static let minimumDigits = 2
        static let horizontalPadding: CGFloat = 8
        static let separatorWidth: CGFloat = 0.5
    }
}
#endif
