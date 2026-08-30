import SwiftUI
import UIKit

struct StudioVideoView: UIViewRepresentable {
    var view: UIView?

    func makeUIView(context: Context) -> VideoContainerView {
        let container = VideoContainerView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        container.attach(view)
        return container
    }

    func updateUIView(_ container: VideoContainerView, context: Context) {
        container.attach(view)
    }
}

/// Holds a RealtimeKit renderer without detaching it on SwiftUI refreshes.
/// Removing a camera preview from the hierarchy restarts the capture session
/// and looks like a blink.
final class VideoContainerView: UIView {
    private weak var attached: UIView?

    func attach(_ video: UIView?) {
        if attached === video, video == nil || video?.superview === self {
            return
        }
        attached?.removeFromSuperview()
        attached = video
        guard let video else { return }
        video.translatesAutoresizingMaskIntoConstraints = false
        addSubview(video)
        NSLayoutConstraint.activate([
            video.leadingAnchor.constraint(equalTo: leadingAnchor),
            video.trailingAnchor.constraint(equalTo: trailingAnchor),
            video.topAnchor.constraint(equalTo: topAnchor),
            video.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
