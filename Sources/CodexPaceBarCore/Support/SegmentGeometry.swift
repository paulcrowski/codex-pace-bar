import Foundation

public enum SegmentGeometry {
    public static func markerX(barStartX: Double, barWidth: Double, elapsedFraction: Double) -> Double {
        barStartX + clamp(elapsedFraction, 0, 1) * barWidth
    }
}
