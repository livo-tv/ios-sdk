import LivoStudioAPI
import SwiftUI
import UIKit

/// Native studio room. First-party apps inject a minted `StudioSession`;
/// partners should prefer `LivoHostStudioView` / `LivoGuestStudioView`.
public struct StudioRoomView: View {
    @Environment(\.studioTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: StudioRoomModel

    public init(
        session: StudioSession,
        apiURL: URL = LivoAPIConfiguration.productionAPIURL,
        meeting: MeetingControlling? = nil,
        onEvent: ((StudioEvent) -> Void)? = nil
    ) {
        _model = StateObject(
            wrappedValue: StudioRoomModel(
                session: session,
                apiURL: apiURL,
                meeting: meeting,
                onEvent: onEvent
            )
        )
    }

    /// Test / first-party injection of an already-built model.
    public init(model: StudioRoomModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            switch model.phase {
            case .connecting:
                StudioSkeletonView()
            case .waitlisted:
                waiting("Waiting for the host to admit you")
            case .rejected:
                waiting("The host declined this join request")
            case .ended:
                waiting("This broadcast has ended")
            case .left:
                waiting("You left the studio")
            case let .failed(message):
                waiting(message)
            case .inRoom:
                room
            }
            if !model.toasts.isEmpty {
                StudioToastOverlay(toasts: model.toasts, onDismiss: model.dismissToast)
            }
        }
        .modifier(StudioPreferredColorScheme(mode: theme.mode))
        .task { await model.start() }
        .onDisappear { model.tearDown() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.handleSceneBackgrounded()
            case .active:
                Task { await model.handleSceneBecameActive() }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $model.showingSettings) {
            StudioSettingsSheet(model: model)
        }
        .sheet(isPresented: $model.showingMore) {
            StudioMoreDrawer(model: model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: sidePanelPresented) {
            StudioSidePanel(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Stop this broadcast?",
            isPresented: Binding(
                get: { model.confirmStop },
                set: { if !$0 { model.confirmStop = false } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop broadcast", role: .destructive) {
                Task { await model.stopConfirmed() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Viewers will be disconnected and the studio will close.")
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { model.pendingConfirm != nil },
                set: { if !$0 { model.pendingConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            confirmActions
            Button("Cancel", role: .cancel) { model.pendingConfirm = nil }
        } message: {
            Text(confirmMessage)
        }
    }

    private var usesPadChrome: Bool {
        StudioStageLayout.prefersRegularLayout(
            regularWidth: horizontalSizeClass == .regular,
            regularHeight: verticalSizeClass == .regular,
            isPad: UIDevice.current.userInterfaceIdiom == .pad
        )
    }

    private var sidePanelPresented: Binding<Bool> {
        Binding(
            get: { model.phase == .inRoom && model.selectedTab != nil },
            set: { if !$0 { model.selectedTab = nil } }
        )
    }

    private var room: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            ParticipantGridView(model: model, regularWidth: usesPadChrome)
                .padding(8)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: 56)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 76)
                }
            VStack(spacing: 0) {
                StudioHeaderBar(model: model)
                Spacer(minLength: 0)
            }
            VStack {
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    StudioChatOverlay(model: model)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 88)
                .safeAreaPadding(.bottom)
            }
            if let pip = model.stageArrangement.pip {
                StudioSelfPiPView(model: model, tile: pip)
            }
            VStack {
                Spacer(minLength: 0)
                StudioToolbar(model: model)
            }
        }
        .foregroundStyle(theme.foreground)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.selectedTab)
    }

    private var confirmTitle: String {
        switch model.pendingConfirm {
        case .kick: "Remove this person?"
        case .mute: "Mute this person?"
        case .stopCamera: "Stop their camera?"
        case .stopScreen: "Stop their screen share?"
        case .takeOffStage: "Take them off stage?"
        case .none: ""
        }
    }

    private var confirmMessage: String {
        switch model.pendingConfirm {
        case .kick: "They will be removed from the studio."
        case .mute: "Their microphone will be turned off."
        case .stopCamera: "Their camera will be turned off."
        case .stopScreen: "Their screen share will be turned off."
        case .takeOffStage: "They will become audience and leave the stage."
        case .none: ""
        }
    }

    @ViewBuilder
    private var confirmActions: some View {
        switch model.pendingConfirm {
        case .kick:
            Button("Kick", role: .destructive) { model.confirmKick() }
        case .mute:
            Button("Mute", role: .destructive) { model.confirmMute() }
        case .stopCamera:
            Button("Stop camera", role: .destructive) { model.confirmStopCamera() }
        case .stopScreen:
            Button("Stop screen share", role: .destructive) { model.confirmStopScreen() }
        case .takeOffStage:
            Button("Take off stage", role: .destructive) {
                if case let .takeOffStage(participant) = model.pendingConfirm {
                    model.takeOffStage(participant)
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func waiting(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(theme.primary)
                .opacity(model.phase == .connecting ? 1 : 0)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.foreground)
            if case .failed = model.phase {
                Button("Reconnect") {
                    Task { await model.reconnect() }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primary)
                Button("Close") {
                    model.dismissRoom()
                    dismiss()
                }
                .buttonStyle(.bordered)
            } else if model.phase.isTerminal {
                Button("Close") {
                    model.dismissRoom()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.primary)
            }
        }
        .padding(24)
        .safeAreaPadding()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct StudioSkeletonView: View {
    @Environment(\.studioTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: theme.radius)
                .fill(theme.foreground.opacity(0.08))
                .aspectRatio(16 / 9, contentMode: .fit)
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.foreground.opacity(0.08))
                .frame(height: 20)
            HStack {
                Circle().fill(theme.foreground.opacity(0.08)).frame(width: 48, height: 48)
                Circle().fill(theme.foreground.opacity(0.08)).frame(width: 48, height: 48)
                Circle().fill(theme.foreground.opacity(0.08)).frame(width: 48, height: 48)
            }
        }
        .padding(24)
        .safeAreaPadding()
        .redacted(reason: .placeholder)
        .opacity(reduceMotion ? 1 : 0.85)
        .accessibilityLabel("Connecting to studio")
    }
}
