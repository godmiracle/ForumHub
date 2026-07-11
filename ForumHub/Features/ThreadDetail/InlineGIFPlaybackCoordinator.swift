import CoreGraphics
import Foundation

struct InlineGIFPlaybackCoordinator {
    let viewportBuffer: CGFloat
    let maximumSimultaneousGIFs: Int

    init(viewportBuffer: CGFloat = 180, maximumSimultaneousGIFs: Int = 3) {
        self.viewportBuffer = viewportBuffer
        self.maximumSimultaneousGIFs = maximumSimultaneousGIFs
    }

    func activePlaybackIDs(
        from candidates: [ThreadDetailGIFFrameCandidate],
        viewportHeight: CGFloat
    ) -> Set<UUID> {
        let viewportHeight = max(viewportHeight, 1)
        let expandedTop = -viewportBuffer
        let expandedBottom = viewportHeight + viewportBuffer

        return Set(
            candidates
                .filter { candidate in
                    candidate.frame.maxY >= expandedTop && candidate.frame.minY <= expandedBottom
                }
                .sorted { lhs, rhs in
                    abs(lhs.frame.midY - viewportHeight / 2) < abs(rhs.frame.midY - viewportHeight / 2)
                }
                .prefix(max(maximumSimultaneousGIFs, 0))
                .map(\.id)
        )
    }
}
