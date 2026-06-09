import Foundation

public enum SegmentGeometry {
    public static func fills(usedFraction: Double, segmentCount: Int = 7) -> [Double] {
        guard segmentCount > 0 else {
            return []
        }

        let clampedFraction = clamp(usedFraction, 0, 1)
        return (0..<segmentCount).map { index in
            clamp(clampedFraction * Double(segmentCount) - Double(index), 0, 1)
        }
    }

    public static func markerX(barStartX: Double, barWidth: Double, elapsedFraction: Double) -> Double {
        barStartX + clamp(elapsedFraction, 0, 1) * barWidth
    }
}
