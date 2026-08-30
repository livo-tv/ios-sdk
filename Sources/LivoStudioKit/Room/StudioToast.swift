import AudioToolbox
import SwiftUI
import UIKit

public struct StudioToast: Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case info
        case success
        case warning
    }

    public var id: UUID
    public var message: String
    public var kind: Kind

    public init(id: UUID = UUID(), message: String, kind: Kind = .info) {
        self.id = id
        self.message = message
        self.kind = kind
    }
}

enum StudioSoundKind {
    case request
    case chat
}

enum StudioSounds {
    static func play(_ kind: StudioSoundKind) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let sound: SystemSoundID = switch kind {
        case .request: 1007
        case .chat: 1104
        }
        AudioServicesPlaySystemSound(sound)
    }
}

struct StudioToastOverlay: View {
    var toasts: [StudioToast]
    var onDismiss: (UUID) -> Void
    @Environment(\.studioTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts) { toast in
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: toast.kind))
                        .frame(width: 8, height: 8)
                    Text(toast.message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        onDismiss(toast.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(theme.foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radius))
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }

    private func color(for kind: StudioToast.Kind) -> Color {
        switch kind {
        case .info: theme.primary
        case .success: theme.primary
        case .warning: theme.destructive
        }
    }
}
