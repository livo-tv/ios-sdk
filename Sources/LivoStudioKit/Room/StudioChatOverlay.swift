import SwiftUI

struct StudioChatOverlay: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if model.selectedTab != .chat,
               let preview = StudioChatGrouping.overlayPreview(
                   messages: model.messages,
                   selfUserId: model.selfUserId,
                   now: context.date.timeIntervalSince1970
               )
            {
                bubble(preview)
                    .transition(reduceMotion ? .identity : .opacity)
                    .onTapGesture { model.selectedTab = .chat }
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityHint("Opens chat")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.messages.last?.id)
    }

    private func bubble(_ group: StudioChatGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StudioAvatarView(name: group.name, picture: nil, diameter: 18)
                Text(group.mine ? "You" : group.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            ForEach(group.rows) { message in
                Text(message.text)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 220, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(accessibility(group))
    }

    private func accessibility(_ group: StudioChatGroup) -> String {
        let who = group.mine ? "You" : group.name
        let lines = group.rows.map(\.text).joined(separator: ", ")
        return "\(who): \(lines)"
    }
}
