import Foundation
import Testing
import EHDomain

struct DeviceSyncLiveActivityTests {
    @Test("Live Activity content keeps progress bounded and prefers byte progress")
    func contentStateProgress() throws {
        let state = DeviceSyncActivityContentState(
            phase: .receiving,
            direction: .receiving,
            remoteDeviceName: "iPhone",
            completedGalleries: 4,
            totalGalleries: 2,
            completedBytes: 100,
            totalBytes: 200,
            currentPageIndex: -1
        )

        #expect(state.completedGalleries == 4)
        #expect(state.totalGalleries == 2)
        #expect(state.completedBytes == 100)
        #expect(state.totalBytes == 200)
        #expect(state.currentPageIndex == -1)
        #expect(state.fraction == 0.5)
    }

    @Test("Live Activity content round-trips through Codable")
    func contentStateCodableRoundTrip() throws {
        let state = DeviceSyncActivityContentState(
            phase: .comparingResults,
            remoteDeviceName: "Mac",
            completedGalleries: 3,
            totalGalleries: 5,
            completedBytes: 120,
            totalBytes: 240,
            currentGalleryTitle: "同步中的画廊",
            estimatedRemainingSeconds: 12.5,
            transportDescription: "Wi-Fi Aware"
        )

        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(DeviceSyncActivityContentState.self, from: data) == state)
    }
}
