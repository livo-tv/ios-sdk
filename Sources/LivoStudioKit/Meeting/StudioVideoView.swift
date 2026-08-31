import SwiftUI
import UIKit

struct StudioVideoView: UIViewRepresentable {
    var view: UIView?
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> VideoContainerView {
        let container = VideoContainerView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        container.attach(view, contentMode: contentMode)
        return container
    }

    func updateUIView(_ container: VideoContainerView, context: Context) {
        container.attach(view, contentMode: contentMode)
    }
}

/// Holds a RealtimeKit renderer without detaching it on SwiftUI refreshes.
/// Removing a camera preview from the hierarchy restarts the capture session
/// and looks like a blink.
final class VideoContainerView: UIView {
    private weak var attached: UIView?

    func attach(_ video: UIView?, contentMode: UIView.ContentMode = .scaleAspectFill) {
        video?.contentMode = contentMode
        if attached === video, video == nil || video?.superview === self {
            return
        }
        attached?.removeFromSuperview()
        attached = video
        guard let video else { return }
        video.translatesAutoresizingMaskIntoConstraints = false
        video.contentMode = contentMode
        addSubview(video)
        NSLayoutConstraint.activate([
            video.leadingAnchor.constraint(equalTo: leadingAnchor),
            video.trailingAnchor.constraint(equalTo: trailingAnchor),
            video.topAnchor.constraint(equalTo: topAnchor),
            video.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
