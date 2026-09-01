import LivoStudioAPI
import SwiftUI

struct StudioChatGroup: Identifiable, Hashable {
    var userId: String
    var name: String
    var mine: Bool
    var rows: [StudioChatMessage]

    var id: String { rows.first?.id ?? userId }
}

enum StudioChatGrouping {
    static let maxTextLimit = 2000

    static func publicMessages(_ messages: [StudioChatMessage]) -> [StudioChatMessage] {
        messages.filter { $0.targetUserIds.isEmpty }
    }

    static func group(_ messages: [StudioChatMessage], selfUserId: String?) -> [StudioChatGroup] {
        var groups: [StudioChatGroup] = []
        for row in publicMessages(messages) {
            let mine = selfUserId.map { $0 == row.userId } ?? false
            if var last = groups.last, last.userId == row.userId, last.mine == mine {
                last.rows.append(row)
                groups[groups.count - 1] = last
                continue
            }
            groups.append(StudioChatGroup(userId: row.userId, name: row.name, mine: mine, rows: [row]))
        }
        return groups
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    static let overlayMaxAge: TimeInterval = 6
    static let overlayMaxLines = 3

    static func overlayPreview(
        messages: [StudioChatMessage],
        selfUserId: String?,
        now: TimeInterval,
        maxAge: TimeInterval = overlayMaxAge,
        maxLines: Int = overlayMaxLines
    ) -> StudioChatGroup? {
        let groups = group(messages, selfUserId: selfUserId)
        guard var last = groups.last, let newest = last.rows.last else { return nil }
        guard now - newest.time <= maxAge else { return nil }
        if last.rows.count > maxLines {
            last.rows = Array(last.rows.suffix(maxLines))
        }
        return last
    }
}

struct StudioChatPanel: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            chatGroup(group)
                                .id(group.rows.last?.id)
                        }
                    }
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = groups.last?.rows.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            composer
        }
    }

    private var groups: [StudioChatGroup] {
        StudioChatGrouping.group(model.messages, selfUserId: model.selfUserId)
    }

    private func chatGroup(_ group: StudioChatGroup) -> some View {
        VStack(alignment: group.mine ? .trailing : .leading, spacing: 4) {
            if !group.mine {
                HStack(spacing: 6) {
                    Text(StudioChatGrouping.initials(group.name))
                        .font(.caption2.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(theme.foreground.opacity(0.16), in: Circle())
                    Text(group.name)
                        .font(.caption2)
                        .foregroundStyle(theme.secondary)
                }
            }
            ForEach(group.rows) { message in
                Text(message.text)
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(group.mine ? theme.background : theme.foreground)
                    .background(
                        group.mine ? theme.primary : theme.foreground.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
        .padding(group.mine ? .leading : .trailing, 36)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1 ... 5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(theme.foreground.opacity(0.08), in: Capsule())
                .onChange(of: draft) { _, next in
                    if next.count > StudioChatGrouping.maxTextLimit {
                        draft = String(next.prefix(StudioChatGrouping.maxTextLimit))
                    }
                }
            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canSend ? theme.background : theme.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        canSend ? theme.primary : theme.foreground.opacity(0.12),
                        in: Circle()
                    )
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.top, 8)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        model.sendChat(draft)
        draft = ""
    }
}
