import SwiftUI

/// Draggable in-app self-view. System `AVPictureInPictureController` needs an
/// `AVPlayer`; RealtimeKit exposes a `UIView`, so we float that renderer instead.
struct StudioSelfPiPView: View {
    @ObservedObject var model: StudioRoomModel
    var tile: StudioDisplayTile
    @Environment(\.studioTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var corner = Corner.bottomTrailing
    @State private var drag: CGSize = .zero

    private enum Corner: CaseIterable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    private var participant: StudioParticipant { tile.participant }

    private var pipSize: CGSize {
        horizontalSizeClass == .regular
            ? CGSize(width: 150, height: 200)
            : CGSize(width: 110, height: 150)
    }

    var body: some View {
        GeometryReader { geo in
            let size = pipSize
            let origin = snappedOrigin(corner: corner, canvas: geo.size, pip: size)
            pipTile
                .frame(width: size.width, height: size.height)
                .offset(x: origin.x + drag.width, y: origin.y + drag.height)
                .gesture(dragGesture(canvas: geo.size, pip: size, origin: origin))
        }
        .padding(.horizontal, 12)
        .padding(.top, 56)
        .padding(.bottom, 88)
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your video")
    }

    private var pipTile: some View {
        let _ = model.rendererRevision
        let video = model.videoView(for: tile)
        return ZStack(alignment: .bottomLeading) {
            Color(white: 0.13)
            StudioVideoView(view: video, contentMode: .scaleAspectFill)
            if video == nil {
                StudioAvatarView(
                    name: participant.name,
                    picture: participant.picture,
                    diameter: 48
                )
            }
            HStack(spacing: 4) {
                if !participant.audioEnabled {
                    Image(systemName: "mic.slash.fill")
                        .font(.caption2)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }

    private func dragGesture(canvas: CGSize, pip: CGSize, origin: CGPoint) -> some Gesture {
        DragGesture()
            .onChanged { value in
                drag = value.translation
            }
            .onEnded { value in
                let center = CGPoint(
                    x: origin.x + value.translation.width + pip.width / 2,
                    y: origin.y + value.translation.height + pip.height / 2
                )
                let next = nearestCorner(to: center, canvas: canvas)
                if reduceMotion {
                    corner = next
                    drag = .zero
                } else {
                    withAnimation(.spring(duration: 0.28, bounce: 0.12)) {
                        corner = next
                        drag = .zero
                    }
                }
            }
    }

    private func snappedOrigin(corner: Corner, canvas: CGSize, pip: CGSize) -> CGPoint {
        let maxX = max(0, canvas.width - pip.width)
        let maxY = max(0, canvas.height - pip.height)
        switch corner {
        case .topLeading:
            return CGPoint(x: 0, y: 0)
        case .topTrailing:
            return CGPoint(x: maxX, y: 0)
        case .bottomLeading:
            return CGPoint(x: 0, y: maxY)
        case .bottomTrailing:
            return CGPoint(x: maxX, y: maxY)
        }
    }

    private func nearestCorner(to point: CGPoint, canvas: CGSize) -> Corner {
        let size = pipSize
        return Corner.allCases.min { lhs, rhs in
            let left = snappedOrigin(corner: lhs, canvas: canvas, pip: size)
            let right = snappedOrigin(corner: rhs, canvas: canvas, pip: size)
            return distance(point, CGPoint(x: left.x + size.width / 2, y: left.y + size.height / 2))
                < distance(point, CGPoint(x: right.x + size.width / 2, y: right.y + size.height / 2))
        } ?? .bottomTrailing
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
