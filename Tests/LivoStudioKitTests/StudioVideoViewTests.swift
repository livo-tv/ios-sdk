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
