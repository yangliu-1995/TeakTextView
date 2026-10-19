#if canImport(UIKit)
import UIKit

/// A TextKit-owned visual row and its position in a bounded drawing tile.
@MainActor
struct TeakTextRenderRow {
    let line: NSTextLineFragment
    let origin: CGPoint
    let range: NSRange
}
#endif
