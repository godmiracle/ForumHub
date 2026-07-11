import CoreGraphics
import Foundation
import Testing
@testable import ForumHub

struct InlineGIFPlaybackCoordinatorTests {
    @Test func selectsClosestVisibleGIFsWithinConfiguredLimit() {
        let ids = (0..<4).map { _ in UUID() }
        let candidates = [
            ThreadDetailGIFFrameCandidate(id: ids[0], frame: CGRect(x: 0, y: -160, width: 100, height: 80)),
            ThreadDetailGIFFrameCandidate(id: ids[1], frame: CGRect(x: 0, y: 80, width: 100, height: 80)),
            ThreadDetailGIFFrameCandidate(id: ids[2], frame: CGRect(x: 0, y: 300, width: 100, height: 80)),
            ThreadDetailGIFFrameCandidate(id: ids[3], frame: CGRect(x: 0, y: 800, width: 100, height: 80))
        ]

        let active = InlineGIFPlaybackCoordinator(
            viewportBuffer: 120,
            maximumSimultaneousGIFs: 2
        ).activePlaybackIDs(from: candidates, viewportHeight: 400)

        #expect(active == Set([ids[1], ids[2]]))
    }

    @Test func ignoresOffscreenGIFsAndSupportsDisabledPlayback() {
        let id = UUID()
        let candidate = ThreadDetailGIFFrameCandidate(
            id: id,
            frame: CGRect(x: 0, y: 700, width: 100, height: 80)
        )

        #expect(
            InlineGIFPlaybackCoordinator().activePlaybackIDs(
                from: [candidate],
                viewportHeight: 400
            ).isEmpty
        )
        #expect(
            InlineGIFPlaybackCoordinator(maximumSimultaneousGIFs: 0).activePlaybackIDs(
                from: [ThreadDetailGIFFrameCandidate(id: id, frame: CGRect(x: 0, y: 20, width: 100, height: 80))],
                viewportHeight: 400
            ).isEmpty
        )
    }
}
