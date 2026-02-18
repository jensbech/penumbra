import AppKit

final class OverlayView: NSView {
    var opacity: CGFloat = 0.4 {
        didSet { needsDisplay = true }
    }

    /// Corner radius read from the focused window via the window server.
    var cornerRadius: CGFloat = 10 {
        didSet { needsDisplay = true }
    }

    /// The focused window rect in screen coordinates (AppKit bottom-left origin).
    var cutoutRect: NSRect? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(opacity).cgColor)

        if let cutout = cutoutRect {
            // Clip cutout to this view's bounds
            let clipped = cutout.intersection(bounds)
            if !clipped.isNull && !clipped.isEmpty {
                // Determine which edges extend to/beyond the screen boundary.
                // Those corners should be square; free-floating corners get rounded.
                let baseRadius = cornerRadius
                let threshold: CGFloat = 1
                let topFlush    = cutout.maxY >= bounds.maxY - threshold
                let bottomFlush = cutout.minY <= bounds.minY + threshold
                let leftFlush   = cutout.minX <= bounds.minX + threshold
                let rightFlush  = cutout.maxX >= bounds.maxX - threshold

                let rTL = (topFlush || leftFlush)     ? 0 : baseRadius
                let rTR = (topFlush || rightFlush)    ? 0 : baseRadius
                let rBL = (bottomFlush || leftFlush)  ? 0 : baseRadius
                let rBR = (bottomFlush || rightFlush) ? 0 : baseRadius

                // Even-odd fill: full bounds minus per-corner-rounded cutout
                ctx.beginPath()
                ctx.addRect(bounds)
                ctx.addPath(Self.roundedRectPath(clipped, topLeft: rTL, topRight: rTR, bottomLeft: rBL, bottomRight: rBR))
                ctx.drawPath(using: .eoFill)
                return
            }
        }

        // No cutout or cutout doesn't intersect — dim everything
        ctx.fill(bounds)
    }

    /// Build a rounded-rect CGPath with independent per-corner radii.
    private static func roundedRectPath(
        _ rect: CGRect,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomLeft: CGFloat,
        bottomRight: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()

        // Start at bottom-left, trace clockwise (AppKit coords: Y-up)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + bottomLeft))

        // Bottom-left corner
        if bottomLeft > 0 {
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.minX + bottomLeft, y: rect.minY),
                        radius: bottomLeft)
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        // Bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX - bottomRight, y: rect.minY))
        if bottomRight > 0 {
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY + bottomRight),
                        radius: bottomRight)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // Top-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - topRight))
        if topRight > 0 {
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.maxX - topRight, y: rect.maxY),
                        radius: topRight)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        // Top-left corner
        path.addLine(to: CGPoint(x: rect.minX + topLeft, y: rect.maxY))
        if topLeft > 0 {
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                        tangent2End: CGPoint(x: rect.minX, y: rect.maxY - topLeft),
                        radius: topLeft)
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}
