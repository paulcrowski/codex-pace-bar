@preconcurrency import AppKit
import Foundation

public final class MenuBarIconRenderer {
    private let segmentCount = 7
    private let size: NSSize

    public init(size: NSSize = NSSize(width: 70, height: 18)) {
        self.size = size
    }

    public func render(
        snapshot: PaceSnapshot?,
        state: PaceState,
        isStale: Bool = false,
        colorScheme: BarColorScheme = .statusColor
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let isLarge = size.width >= 120
        let horizontalPadding: CGFloat = isLarge ? 4 : 2
        let barStartX = horizontalPadding
        let barWidth = size.width - horizontalPadding * 2
        let gap: CGFloat = isLarge ? 3 : 1.5
        let segmentWidth = (barWidth - CGFloat(segmentCount - 1) * gap) / CGFloat(segmentCount)
        let segmentHeight = min(max(size.height * 0.55, 9), 24)
        let segmentY = (size.height - segmentHeight) / 2

        let bands = colorBands(snapshot: snapshot, state: state, isStale: isStale, colorScheme: colorScheme)
        let emptyColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.35)

        for index in 0..<segmentCount {
            let x = barStartX + CGFloat(index) * (segmentWidth + gap)
            let rect = NSRect(x: x, y: segmentY, width: segmentWidth, height: segmentHeight)
            let path = NSBezierPath(rect: rect)

            emptyColor.setFill()
            path.fill()

            drawBands(
                bands,
                inSegment: index,
                segmentRect: rect,
                clipPath: path
            )
        }

        if let snapshot, state.isValidPaceState, !isStale {
            drawMarker(elapsedFraction: snapshot.elapsedFraction, barStartX: Double(barStartX), barWidth: Double(barWidth))
        }

        if state == .error || isStale {
            drawWarningIndicator()
        }

        image.isTemplate = false
        return image
    }

    private func colorBands(
        snapshot: PaceSnapshot?,
        state: PaceState,
        isStale: Bool,
        colorScheme: BarColorScheme
    ) -> [ColorBand] {
        guard let snapshot else {
            return []
        }

        if isStale || !state.isValidPaceState || colorScheme == .statusColor {
            return [
                ColorBand(start: 0, end: snapshot.usedFraction, color: color(for: state, isStale: isStale))
            ]
        }

        let used = clamp(snapshot.usedFraction, 0, 1)
        let marker = clamp(snapshot.elapsedFraction, 0, 1)

        if used < marker {
            return [
                ColorBand(start: 0, end: used, color: .systemBlue),
                ColorBand(start: used, end: marker, color: .systemGreen)
            ]
        }

        if used > marker {
            return [
                ColorBand(start: 0, end: marker, color: .systemBlue),
                ColorBand(start: marker, end: used, color: .systemRed)
            ]
        }

        return [
            ColorBand(start: 0, end: marker, color: .systemBlue)
        ]
    }

    private func drawBands(_ bands: [ColorBand], inSegment index: Int, segmentRect rect: NSRect, clipPath: NSBezierPath) {
        let segmentStart = Double(index) / Double(segmentCount)
        let segmentEnd = Double(index + 1) / Double(segmentCount)

        for band in bands {
            let overlapStart = max(segmentStart, band.start)
            let overlapEnd = min(segmentEnd, band.end)
            guard overlapEnd > overlapStart else {
                continue
            }

            let localStart = (overlapStart - segmentStart) / (segmentEnd - segmentStart)
            let localEnd = (overlapEnd - segmentStart) / (segmentEnd - segmentStart)
            let fillX = rect.minX + rect.width * CGFloat(localStart)
            let fillWidth = rect.width * CGFloat(localEnd - localStart)

            NSGraphicsContext.current?.saveGraphicsState()
            clipPath.addClip()
            band.color.setFill()
            NSRect(x: fillX, y: rect.minY, width: fillWidth, height: rect.height).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }

    private func color(for state: PaceState, isStale: Bool) -> NSColor {
        if isStale {
            return .systemGray
        }

        switch state {
        case .belowPace:
            return .systemGreen
        case .onPace:
            return .systemBlue
        case .abovePace:
            return .systemRed
        case .loading, .error:
            return .systemGray
        }
    }

    private func drawMarker(elapsedFraction: Double, barStartX: Double, barWidth: Double) {
        let markerX = CGFloat(SegmentGeometry.markerX(barStartX: barStartX, barWidth: barWidth, elapsedFraction: elapsedFraction))
        let markerWidth: CGFloat = size.width >= 120 ? 2.5 : 1.5
        let markerRect = NSRect(x: markerX - markerWidth / 2, y: 2, width: markerWidth, height: size.height - 4)
        let path = NSBezierPath(roundedRect: markerRect, xRadius: markerWidth / 2, yRadius: markerWidth / 2)

        NSColor.controlBackgroundColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        path.stroke()

        NSColor.labelColor.withAlphaComponent(0.9).setFill()
        path.fill()
    }

    private func drawWarningIndicator() {
        let rect = NSRect(x: size.width - 6, y: size.height - 7, width: 4, height: 4)
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}

private struct ColorBand {
    let start: Double
    let end: Double
    let color: NSColor
}
