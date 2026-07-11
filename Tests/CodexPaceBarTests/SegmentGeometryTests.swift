import CodexPaceBarCore
import Testing

@Suite
struct SegmentGeometryTests {
    @Test
    func markerPosition() {
        #expect(SegmentGeometry.markerX(barStartX: 2, barWidth: 42, elapsedFraction: 0) == 2)
        #expect(SegmentGeometry.markerX(barStartX: 2, barWidth: 42, elapsedFraction: 0.5) == 23)
        #expect(SegmentGeometry.markerX(barStartX: 2, barWidth: 42, elapsedFraction: 1) == 44)
    }
}
