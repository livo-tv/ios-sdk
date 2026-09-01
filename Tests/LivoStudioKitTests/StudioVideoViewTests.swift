import Testing
import UIKit
@testable import LivoStudioKit

@MainActor
struct StudioVideoViewTests {
    @Test func attachDoesNotDetachSameView() {
        let container = VideoContainerView()
        let video = SuperviewProbe()
        container.attach(video)
        #expect(video.superview === container)
        container.attach(video)
        #expect(video.removeCount == 0)
        #expect(video.superview === container)
    }

    @Test func attachReplacesDifferentView() {
        let container = VideoContainerView()
        let first = SuperviewProbe()
        let second = UIView()
        container.attach(first)
        container.attach(second)
        #expect(first.removeCount == 1)
        #expect(first.superview == nil)
        #expect(second.superview === container)
    }

    @Test func attachAppliesContentMode() {
        let container = VideoContainerView()
        let video = UIView()
        container.attach(video, contentMode: .scaleAspectFit)
        #expect(video.contentMode == .scaleAspectFit)
        container.attach(video, contentMode: .scaleAspectFill)
        #expect(video.contentMode == .scaleAspectFill)
    }

    @Test func rendererCacheDropsOnInvalidate() {
        let cache = StudioVideoRendererCache()
        let first = UIView()
        let second = UIView()
        cache.store(first, participantId: "g1", screenShare: false)
        #expect(cache.view(for: "g1", screenShare: false) === first)
        cache.invalidate(participantId: "g1", screenShare: false)
        #expect(cache.view(for: "g1", screenShare: false) == nil)
        cache.store(first, participantId: "g1", screenShare: false)
        cache.store(second, participantId: "g1", screenShare: true)
        cache.invalidateAll(for: "g1")
        #expect(cache.view(for: "g1", screenShare: false) == nil)
        #expect(cache.view(for: "g1", screenShare: true) == nil)
    }

    @Test func attachNilClearsRenderer() {
        let container = VideoContainerView()
        let video = SuperviewProbe()
        container.attach(video)
        container.attach(nil)
        #expect(video.removeCount == 1)
        #expect(container.subviews.isEmpty)
        container.attach(nil)
        #expect(video.removeCount == 1)
    }
}

private final class SuperviewProbe: UIView {
    var removeCount = 0

    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil, superview != nil {
            removeCount += 1
        }
        super.willMove(toSuperview: newSuperview)
    }
}
