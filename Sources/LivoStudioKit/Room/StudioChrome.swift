import LivoStudioAPI
import SwiftUI

struct StudioHeaderBar: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Text(model.session.stream.title)
                .font(.headline)
                .lineLimit(1)
                .frame(minWidth: 0, alignment: .leading)
            Spacer(minLength: 8)
            if model.isLive {
                LiveBadge(startedAt: model.liveStartedAt)
            } else if model.streamStatus == "preview" {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.foreground.opacity(0.12), in: Capsule())
            }
            Button {
                model.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Studio settings")
            .frame(width: 44, height: 44)
            if model.canPublish {
                Button {
                    Task { await model.publish() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text(model.publishing ? "Going live" : "Go Live")
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .tint(theme.live)
                .disabled(model.publishing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .safeAreaPadding(.top)
        .background(theme.background.opacity(0.92))
    }
}

struct LiveBadge: View {
    var startedAt: Date?
    @Environment(\.studioTheme) private var theme
    @State private var now = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Circle().fill(theme.live).frame(width: 8, height: 8)
                Text("LIVE")
                    .font(.caption.weight(.bold))
                if let startedAt {
                    Text(elapsed(from: startedAt, now: context.date))
                        .font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.live.opacity(0.25), in: Capsule())
            .accessibilityLabel(accessibility)
        }
    }

    private var accessibility: String {
        if let startedAt {
            return "Live, elapsed \(elapsed(from: startedAt, now: now))"
        }
        return "Live"
    }

    private func elapsed(from start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remain = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remain)
        }
        return String(format: "%d:%02d", minutes, remain)
    }
}

struct ParticipantGridView: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme

    var body: some View {
        let layout = model.stageArrangement
        GeometryReader { geo in
            VStack(spacing: 8) {
                if layout.spotlight.isEmpty, layout.strip.isEmpty {
                    emptyStage
                } else if !layout.spotlight.isEmpty {
                    spotlightLayout(layout, in: geo.size)
                } else {
                    grid(layout.strip, in: geo.size)
                }
            }
            .padding(8)
        }
    }

    private var emptyStage: some View {
        VStack(spacing: 12) {
            Text("No one is on stage")
                .font(.headline)
                .foregroundStyle(theme.secondary)
            if !model.isModerator, !model.selfOnStage {
                Button("Ask to join stage") { model.requestStage() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func spotlightLayout(_ layout: StudioStageArrangement, in size: CGSize) -> some View {
        VStack(spacing: 8) {
            if let focus = layout.spotlight.first {
                ParticipantTile(model: model, tile: focus)
                    .frame(maxHeight: size.height * (layout.strip.isEmpty ? 1 : 0.68))
            }
            if !layout.strip.isEmpty || layout.overflow > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(layout.strip) { tile in
                            ParticipantTile(model: model, tile: tile)
                                .frame(width: 120, height: 90)
                        }
                        if layout.overflow > 0 {
                            overflowChip(layout.overflow)
                        }
                    }
                }
                .frame(height: 90)
            }
        }
    }

    private func grid(_ tiles: [StudioDisplayTile], in size: CGSize) -> some View {
        let columns = tiles.count > 1 ? 2 : 1
        let rows = max(1, Int(ceil(Double(tiles.count) / Double(columns))))
        let width = size.width / CGFloat(columns)
        let height = size.height / CGFloat(rows)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(tiles) { tile in
                ParticipantTile(model: model, tile: tile)
                    .frame(minWidth: width - 12, minHeight: max(120, height - 12))
                    .id(tile.tileId)
            }
        }
    }

    private func overflowChip(_ count: Int) -> some View {
        Button {
            model.selectedTab = .people
        } label: {
            Text("+\(count)")
                .font(.headline)
                .frame(width: 120, height: 90)
                .background(theme.foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: theme.radius))
        }
        .accessibilityLabel("\(count) more participants")
    }
}

struct ParticipantTile: View {
    @ObservedObject var model: StudioRoomModel
    var tile: StudioDisplayTile
    @Environment(\.studioTheme) private var theme

    private var participant: StudioParticipant { tile.participant }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            StudioVideoView(view: model.videoView(for: tile))
            if tile.kind != .camera {
                Color.black.opacity(tile.kind == .idle ? 0.35 : 0)
                if tile.kind == .idle {
                    Text(initials)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(theme.foreground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack {
                Text(tile.kind == .screen ? "\(participant.name) · screen" : participant.name)
                    .font(.caption.weight(.medium))
                if !participant.audioEnabled {
                    Image(systemName: "mic.slash.fill")
                }
                if participant.pinned {
                    Image(systemName: "pin.fill")
                }
                Spacer()
            }
            .padding(8)
            .foregroundStyle(theme.foreground)
            .background(.black.opacity(0.45))
        }
        .overlay {
            if model.activeSpeakerId == participant.id, !participant.isSelf {
                RoundedRectangle(cornerRadius: theme.radius)
                    .stroke(theme.primary, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius))
        .contextMenu {
            if model.isModerator, !participant.isSelf {
                Button("Mute") { model.pendingConfirm = .mute(participant) }
                Button("Stop camera") { model.pendingConfirm = .stopCamera(participant) }
                Button(participant.pinned ? "Unpin" : "Pin") { model.togglePin(participant) }
                if StudioStageLayout.isOnStage(participant.stageStatus) {
                    Button("Take off stage") { model.pendingConfirm = .takeOffStage(participant) }
                } else {
                    Button("Bring on air") { model.bringOnAir(participant) }
                }
                Button("Kick", role: .destructive) { model.pendingConfirm = .kick(participant) }
            }
        }
        .accessibilityLabel(participant.name)
    }

    private var initials: String {
        StudioChatGrouping.initials(participant.name)
    }
}

struct WaitingRoomStrip: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waiting room")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
            ForEach(model.waitlist) { guest in
                HStack {
                    Text(guest.name)
                    Spacer()
                    Button("Admit") { model.admit(guest) }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.primary)
                        .controlSize(.small)
                    Button("Deny", role: .destructive) { model.deny(guest) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(theme.foreground.opacity(0.06))
    }
}

struct StudioToolbar: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            if model.canUseMediaControls {
                iconButton(model.micOn ? "mic.fill" : "mic.slash.fill", label: model.micOn ? "Mute" : "Unmute") {
                    model.toggleMic()
                }
                iconButton(model.cameraOn ? "video.fill" : "video.slash.fill", label: model.cameraOn ? "Camera off" : "Camera on") {
                    model.toggleCamera()
                }
                iconButton("arrow.triangle.2.circlepath.camera", label: "Switch camera") {
                    model.switchCamera()
                }
                iconButton(model.screenShareOn ? "rectangle.badge.slash" : "rectangle.dashed.badge.record", label: "Screen share") {
                    model.toggleScreenShare()
                }
            }
            if !model.isModerator {
                stageControl
            }
            Spacer()
            if model.canStop {
                Button(role: .destructive) {
                    model.confirmStop = true
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .tint(theme.destructive)
            } else {
                Button("Leave") { model.leave() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .safeAreaPadding(.bottom)
        .background(theme.background.opacity(0.96))
    }

    @ViewBuilder
    private var stageControl: some View {
        let status = model.selfStageStatus ?? model.selfParticipant?.stageStatus
        switch status {
        case .requestedToJoinStage:
            Button("Cancel request") { model.cancelStageRequest() }
        case .acceptedToJoinStage:
            Button("Joining stage…") {}
                .disabled(true)
        case .onStage:
            Button("Leave stage") { model.leaveStage() }
        case .offStage, .none:
            Button("Ask to join stage") { model.requestStage() }
        }
    }

    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}

struct StudioSidePanel: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tab("People", tab: .people, badge: model.peopleBadge)
                tab("Chat", tab: .chat, badge: model.unreadChat)
            }

            switch model.selectedTab {
            case .people:
                people
            case .chat:
                StudioChatPanel(model: model)
            }
        }
        .padding(12)
        .frame(maxHeight: 240)
        .background(theme.foreground.opacity(0.05))
    }

    private func tab(_ title: String, tab: StudioRoomModel.SideTab, badge: Int) -> some View {
        Button {
            model.selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.primary, in: Capsule())
                        .foregroundStyle(theme.background)
                }
            }
            .font(.subheadline.weight(model.selectedTab == tab ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                model.selectedTab == tab ? theme.foreground.opacity(0.12) : .clear,
                in: Capsule()
            )
        }
        .accessibilityLabel(badge > 0 ? "\(title), \(badge)" : title)
        .accessibilityAddTraits(model.selectedTab == tab ? [.isSelected] : [])
    }

    private var people: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !model.stageRequests.isEmpty {
                    stageRequests
                }
                section("On stage", rows: model.stageParticipants, audience: false)
                if !model.audienceParticipants.isEmpty {
                    section("Audience", rows: model.audienceParticipants, audience: true)
                }
            }
        }
    }

    private var stageRequests: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stage requests")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
            ForEach(model.stageRequests) { request in
                HStack {
                    Text(request.name)
                    Spacer()
                    Button("Bring on air") { model.grantStage(request) }
                        .controlSize(.small)
                    Button("Deny", role: .destructive) { model.denyStage(request) }
                        .controlSize(.small)
                }
            }
        }
    }

    private func section(_ title: String, rows: [StudioParticipant], audience: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondary)
            ForEach(rows) { participant in
                HStack {
                    Text(participant.name)
                    if participant.isSelf { Text("you").foregroundStyle(theme.secondary) }
                    Spacer()
                    if !participant.audioEnabled { Image(systemName: "mic.slash") }
                    if model.isModerator, !participant.isSelf, audience {
                        Button("Bring on air") { model.bringOnAir(participant) }
                            .controlSize(.small)
                        Button("Kick", role: .destructive) { model.pendingConfirm = .kick(participant) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

}
