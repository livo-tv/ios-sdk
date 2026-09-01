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
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(theme.live, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .fixedSize()
                .disabled(model.publishing)
                .accessibilityLabel(model.publishing ? "Going live" : "Go Live")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .safeAreaPadding(.top)
        .safeAreaPadding(.horizontal)
        .background(
            LinearGradient(
                colors: [theme.background.opacity(0.72), theme.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
    var regularWidth: Bool = false
    @Environment(\.studioTheme) private var theme

    private var gap: CGFloat { regularWidth ? 12 : 8 }

    var body: some View {
        let layout = model.stageArrangement
        GeometryReader { geo in
            Group {
                if layout.spotlight.isEmpty, layout.strip.isEmpty {
                    emptyStage
                } else if !layout.spotlight.isEmpty {
                    spotlightLayout(layout, in: geo.size)
                } else {
                    grid(layout.strip, in: geo.size)
                }
            }
            .padding(gap)
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

    @ViewBuilder
    private func spotlightLayout(_ layout: StudioStageArrangement, in size: CGSize) -> some View {
        if regularWidth, !layout.strip.isEmpty || layout.overflow > 0 {
            HStack(spacing: gap) {
                if let focus = layout.spotlight.first {
                    ParticipantTile(model: model, tile: focus)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                verticalStrip(layout)
                    .frame(width: 256)
            }
        } else {
            VStack(spacing: gap) {
                if let focus = layout.spotlight.first {
                    ParticipantTile(model: model, tile: focus)
                        .frame(maxHeight: size.height * (layout.strip.isEmpty ? 1 : 0.68))
                }
                if !layout.strip.isEmpty || layout.overflow > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: gap) {
                            ForEach(layout.strip) { tile in
                                ParticipantTile(model: model, tile: tile)
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .frame(width: 160)
                            }
                            if layout.overflow > 0 {
                                overflowChip(layout.overflow)
                                    .frame(width: 160, height: 90)
                            }
                        }
                    }
                    .frame(height: 90)
                }
            }
        }
    }

    private func verticalStrip(_ layout: StudioStageArrangement) -> some View {
        ScrollView {
            VStack(spacing: gap) {
                ForEach(layout.strip) { tile in
                    ParticipantTile(model: model, tile: tile)
                        .aspectRatio(16 / 9, contentMode: .fit)
                }
                if layout.overflow > 0 {
                    overflowChip(layout.overflow)
                        .aspectRatio(16 / 9, contentMode: .fit)
                }
            }
        }
    }

    private func grid(_ tiles: [StudioDisplayTile], in _: CGSize) -> some View {
        let columns = StudioStageLayout.gridColumns(tileCount: tiles.count, regularWidth: regularWidth)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns),
            spacing: gap
        ) {
            ForEach(tiles) { tile in
                ParticipantTile(model: model, tile: tile)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .id(tile.tileId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func overflowChip(_ count: Int) -> some View {
        Button {
            model.selectedTab = .people
        } label: {
            Text("+\(count)")
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let _ = model.rendererRevision
        let video = model.videoView(for: tile)
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.13)
            StudioVideoView(
                view: video,
                contentMode: tile.kind == .screen ? .scaleAspectFit : .scaleAspectFill
            )
            if video == nil {
                GeometryReader { geo in
                    let diameter = min(min(geo.size.width, geo.size.height) * 0.42, 120)
                    StudioAvatarView(
                        name: participant.name,
                        picture: participant.picture,
                        diameter: max(48, diameter)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            nameBar
        }
        .overlay {
            if model.activeSpeakerId == participant.id, !participant.isSelf {
                RoundedRectangle(cornerRadius: theme.radius)
                    .stroke(theme.primary, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius))
        .contextMenu { hostMenu }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(model.isModerator && !participant.isSelf
            ? "Long-press for host controls"
            : "")
    }

    private var nameBar: some View {
        HStack(spacing: 6) {
            Text(tile.kind == .screen ? "\(participant.name) · screen" : participant.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if !participant.audioEnabled {
                Image(systemName: "mic.slash.fill")
                    .font(.caption2)
            }
            if participant.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    @ViewBuilder
    private var hostMenu: some View {
        if model.isModerator, !participant.isSelf {
            if tile.kind == .screen {
                Button("Stop screen share") { model.pendingConfirm = .stopScreen(participant) }
            } else {
                Button("Mute") { model.pendingConfirm = .mute(participant) }
                Button("Stop camera") { model.pendingConfirm = .stopCamera(participant) }
            }
            Button(participant.pinned ? "Unpin" : "Pin") { model.togglePin(participant) }
            if StudioStageLayout.isOnStage(participant.stageStatus) {
                Button("Take off stage") { model.pendingConfirm = .takeOffStage(participant) }
            } else {
                Button("Bring on air") { model.bringOnAir(participant) }
            }
            Button("Kick", role: .destructive) { model.pendingConfirm = .kick(participant) }
        }
    }

    private var accessibilityLabel: String {
        var parts = [tile.kind == .screen ? "\(participant.name) screen" : participant.name]
        if !participant.audioEnabled { parts.append("muted") }
        if participant.pinned { parts.append("pinned") }
        return parts.joined(separator: ", ")
    }

}

struct StudioToolbar: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if model.canUseMediaControls {
                circleButton(
                    model.micOn ? "mic.fill" : "mic.slash.fill",
                    off: !model.micOn,
                    label: model.micOn ? "Mute" : "Unmute"
                ) {
                    model.toggleMic()
                }
                circleButton(
                    model.cameraOn ? "video.fill" : "video.slash.fill",
                    off: !model.cameraOn,
                    label: model.cameraOn ? "Camera off" : "Camera on"
                ) {
                    model.toggleCamera()
                }
            }
            tabToggle("bubble.left.fill", tab: .chat, label: "Chat", badge: model.unreadChat)
            tabToggle("person.2.fill", tab: .people, label: "People", badge: model.peopleBadge)
            circleButton("ellipsis", label: "More") {
                model.showingMore = true
            }
            endButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom)
    }

    private var endButton: some View {
        Button {
            if model.canStop {
                model.confirmStop = true
            } else {
                model.leave()
            }
        } label: {
            Image(systemName: "phone.down.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(minWidth: 52, minHeight: 44)
                .background(theme.destructive, in: Capsule())
        }
        .accessibilityLabel(model.canStop ? "Stop broadcast" : "Leave")
    }

    private func tabToggle(_ system: String, tab: StudioRoomModel.SideTab, label: String, badge: Int) -> some View {
        Button {
            model.toggleSideTab(tab)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: system)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.primary, in: Capsule())
                        .foregroundStyle(theme.background)
                        .offset(x: 4, y: -2)
                }
            }
        }
        .background(
            model.selectedTab == tab ? theme.foreground.opacity(0.16) : .clear,
            in: Circle()
        )
        .accessibilityLabel(badge > 0 ? "\(label), \(badge)" : label)
        .accessibilityAddTraits(model.selectedTab == tab ? [.isSelected] : [])
    }

    private func circleButton(
        _ system: String,
        off: Bool = false,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(off ? .white : theme.foreground)
                .frame(width: 44, height: 44)
                .background(off ? theme.destructive : theme.foreground.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

struct StudioMoreDrawer: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More")
                .font(.headline)
                .padding(.top, 8)
            if model.canUseMediaControls {
                moreButton("arrow.triangle.2.circlepath.camera", "Switch camera") {
                    model.switchCamera()
                    dismiss()
                }
                moreButton(
                    model.screenShareOn ? "rectangle.dashed.badge.record" : "rectangle.dashed.badge.record",
                    model.screenShareOn ? "Stop share" : "Screen share"
                ) {
                    model.toggleScreenShare()
                    dismiss()
                }
            }
            if !model.isModerator {
                stageControl
            }
            moreButton("gearshape", "Settings") {
                dismiss()
                model.showingSettings = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stageControl: some View {
        let status = model.selfStageStatus ?? model.selfParticipant?.stageStatus
        switch status {
        case .requestedToJoinStage:
            moreButton("hand.raised.slash", "Cancel request") {
                model.cancelStageRequest()
                dismiss()
            }
        case .acceptedToJoinStage:
            moreButton("person.badge.plus", "Joining stage…") {
                model.joinStage()
                dismiss()
            }
        case .onStage:
            moreButton("arrow.down.left.and.arrow.up.right", "Leave stage") {
                model.leaveStage()
                dismiss()
            }
        case .offStage, .none:
            moreButton("hand.raised", "Ask to join stage") {
                model.requestStage()
                dismiss()
            }
        }
    }

    private func moreButton(_ system: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: system)
                    .frame(width: 28)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(theme.foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityLabel(title)
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
                Spacer(minLength: 0)
                Button {
                    model.selectedTab = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close panel")
            }
            Divider()

            switch model.selectedTab {
            case .people:
                people
            case .chat:
                StudioChatPanel(model: model)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background)
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
                if model.isModerator, let guestUrl = model.session.guestUrl, let url = URL(string: guestUrl) {
                    ShareLink(item: url) {
                        Label("Share guest link", systemImage: "square.and.arrow.up")
                    }
                    .controlSize(.small)
                }
                if model.isModerator, !model.waitlist.isEmpty {
                    waitingRoom
                }
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

    private var waitingRoom: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Waiting room")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondary)
                Spacer()
                Menu("Admit all") {
                    Button("Admit all as panelists") { model.admitAll(as: .panelist) }
                    Button("Admit all as audience") { model.admitAll(as: .audience) }
                }
                .controlSize(.small)
            }
            ForEach(model.waitlist) { guest in
                HStack {
                    StudioAvatarView(name: guest.name, picture: guest.picture, diameter: 32)
                    Text(guest.name)
                    Spacer()
                    Menu("Admit") {
                        Button("Admit as panelist") { model.admit(guest, as: .panelist) }
                        Button("Admit as audience") { model.admit(guest, as: .audience) }
                    }
                    .controlSize(.small)
                    Button("Deny", role: .destructive) { model.deny(guest) }
                        .controlSize(.small)
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
                    StudioAvatarView(name: request.name, picture: nil, diameter: 32)
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
                    StudioAvatarView(
                        name: participant.name,
                        picture: participant.picture,
                        diameter: 32
                    )
                    Text(participant.name)
                    if participant.isSelf { Text("you").foregroundStyle(theme.secondary) }
                    Spacer()
                    if !participant.audioEnabled { Image(systemName: "mic.slash") }
                    if model.isModerator, !participant.isSelf {
                        if audience {
                            Button("Bring on air") { model.bringOnAir(participant) }
                                .controlSize(.small)
                        } else {
                            Button("Off air") { model.pendingConfirm = .takeOffStage(participant) }
                                .controlSize(.small)
                        }
                        Button("Kick", role: .destructive) { model.pendingConfirm = .kick(participant) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
