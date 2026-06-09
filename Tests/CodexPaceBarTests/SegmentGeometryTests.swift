import CodexPaceBarCore
import Testing

@Suite
struct SegmentGeometryTests {
    @Test
    func segmentFills() {
        #expect(SegmentGeometry.fills(usedFraction: 0) == [0, 0, 0, 0, 0, 0, 0])
        #expect(SegmentGeometry.fills(usedFraction: 1) == [1, 1, 1, 1, 1, 1, 1])
        #expect(SegmentGeometry.fills(usedFraction: 0.5) == [1, 1, 1, 0.5, 0, 0, 0])
        #expect(SegmentGeometry.fills(usedFraction: 1.0 / 7.0) == [1, 0, 0, 0, 0, 0, 0])
        #expect(SegmentGeometry.fills(usedFraction: 1.5 / 7.0) == [1, 0.5, 0, 0, 0, 0, 0])
    }

    @Test
    func markerPosition() {
        #expect(SegmentGeometry.markerX(barStartX: 2, barWidth: 42, elapsedFraction: 0) == 2)
        #expect(SegmentGeometry.markerX(barStartX: 2, barWidth: 42, elapsedFraction: 0.5) == 23)
        #expect(SegmentGeometry.markerX(barStartX: 2, barWidth: 42, elapsedFraction: 1) == 44)
    }
}
