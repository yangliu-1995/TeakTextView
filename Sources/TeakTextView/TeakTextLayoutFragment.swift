#if canImport(UIKit)
import UIKit

/// Keep native paragraph layout and selection geometry, but avoid asking UIKit
/// to allocate a paragraph-sized bitmap for an arbitrarily long wrapped line.
final class TeakTextLayoutFragment: NSTextLayoutFragment {
    var usesViewportRendering: Bool {
        // The ink bounds walk every visual row. The measured layout frame is
        // already available and suffices to route oversized paragraphs away
        // from a single native bitmap, without rescanning a long line on scroll.
        let bounds = layoutFragmentFrame
        return bounds.width > Constants.maximumNativeSurfaceDimension
            || bounds.height > Constants.maximumNativeSurfaceDimension
            || bounds.width * bounds.height > Constants.maximumNativeSurfaceArea
    }

    override var renderingSurfaceBounds: CGRect {
        usesViewportRendering ? .zero : super.renderingSurfaceBounds
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        // TeakTextRenderView draws these paragraphs into a viewport-sized layer.
        // An empty native surface is intentional: its drawing has no contents.
        guard !usesViewportRendering else { return }
        super.draw(at: point, in: context)
    }
}

private extension TeakTextLayoutFragment {
    enum Constants {
        static let maximumNativeSurfaceDimension: CGFloat = 2048
        // A 3x display needs about 4.5 MiB for this many points in RGBA.
        // A narrow but tall paragraph must not escape the surface budget.
        static let maximumNativeSurfaceArea: CGFloat = 512 * 256
    }
}
#endif
