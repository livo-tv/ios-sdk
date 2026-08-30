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
        HStack(alignment: .bottom) {
            TextField("Message", text: $draft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { sendDraft() }
                .onChange(of: draft) { _, next in
                    if next.count > StudioChatGrouping.maxTextLimit {
                        draft = String(next.prefix(StudioChatGrouping.maxTextLimit))
                    }
                }
            Button("Send") { sendDraft() }
                .disabled(!canSend)
        }
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
