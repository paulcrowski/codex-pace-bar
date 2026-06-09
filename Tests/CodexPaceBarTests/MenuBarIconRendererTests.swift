import AppKit
import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct MenuBarIconRendererTests {
    @Test
    func defaultRendererUsesWiderImage() {
        let image = MenuBarIconRenderer().render(snapshot: nil, state: .loading)

        #expect(image.size.width == 70)
        #expect(image.size.height == 18)
    }

    @Test
    func rendererProducesExpectedImageSize() {
        let renderer = MenuBarIconRenderer(size: NSSize(width: 50, height: 18))
        let snapshot = PaceSnapshot(
            actualUsedPercent: 50,
            remainingPercent: 50,
            idealUsedPercent: 50,
            deltaPercentagePoints: 0,
            usedFraction: 0.5,
            elapsedFraction: 0.5,
            resetAt: Date(),
            state: .onPace,
            fetchedAt: Date(),
            isStale: false
        )

        let image = renderer.render(snapshot: snapshot, state: .onPace)

        #expect(image.size.width == 50)
        #expect(image.size.height == 18)
        #expect(!image.isTemplate)
    }

    @Test
    func largeRendererProducesExpectedImageSize() {
        let image = MenuBarIconRenderer(size: NSSize(width: 260, height: 42)).render(snapshot: nil, state: .loading)

        #expect(image.size.width == 260)
        #expect(image.size.height == 42)
    }

    @Test
    func paceComparisonRendererProducesImage() {
        let snapshot = PaceSnapshot(
            actualUsedPercent: 82,
            remainingPercent: 18,
            idealUsedPercent: 60,
            deltaPercentagePoints: 22,
            usedFraction: 0.82,
            elapsedFraction: 0.60,
            resetAt: Date(),
            state: .abovePace,
            fetchedAt: Date(),
            isStale: false
        )

        let image = MenuBarIconRenderer(size: NSSize(width: 260, height: 42)).render(
            snapshot: snapshot,
            state: .abovePace,
            colorScheme: .paceComparison
        )

        #expect(image.size.width == 260)
        #expect(image.size.height == 42)
    }
}
