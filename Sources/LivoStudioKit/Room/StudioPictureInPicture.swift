import SwiftUI

/// Lightweight in-app picture-in-picture for the local camera tile.
/// System `AVPictureInPictureController` needs an `AVPlayer` or sample-buffer
/// layer; RealtimeKit exposes a `UIView`, so we float that view instead.
public struct StudioPictureInPictureModifier: ViewModifier {
    @Binding var isActive: Bool
    var video: AnyView

    public func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if isActive {
                video
                    .frame(width: 140, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .padding(12)
                    .accessibilityLabel("Picture in picture")
            }
        }
    }
}

public extension View {
    func studioPictureInPicture<Video: View>(isActive: Binding<Bool>, @ViewBuilder video: () -> Video) -> some View {
        modifier(StudioPictureInPictureModifier(isActive: isActive, video: AnyView(video())))
    }
}
