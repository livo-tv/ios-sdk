import LivoStudioAPI
import SwiftUI

/// Partner guest entry: lobby (name + device preflight) then join when the meeting is ready.
public struct LivoGuestStudioView: View {
    @Environment(\.studioTheme) private var theme
    private let guestToken: String
    private let apiURL: URL
    private let onEvent: ((StudioEvent) -> Void)?

    @State private var displayName = ""
    @State private var session: StudioSession?
    @State private var ready = false
    @State private var ended = false
    @State private var errorMessage: String?
    @State private var joining = false

    public init(
        guestToken: String,
        apiURL: URL = LivoAPIConfiguration.productionAPIURL,
        onEvent: ((StudioEvent) -> Void)? = nil
    ) {
        self.guestToken = guestToken
        self.apiURL = apiURL
        self.onEvent = onEvent
    }

    public var body: some View {
        Group {
            if let session {
                StudioRoomView(session: session, apiURL: apiURL, onEvent: onEvent)
            } else if ended {
                Text("This studio has ended")
                    .foregroundStyle(theme.foreground)
                    .safeAreaPadding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                lobby
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .studioTheme(theme)
        .task { await pollReady() }
    }

    private var lobby: some View {
        VStack(spacing: 20) {
            Text("Join studio")
                .font(.title2.weight(.semibold))
            TextField("Your name", text: $displayName)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(theme.destructive)
                    .font(.footnote)
            }
            Button {
                Task { await join() }
            } label: {
                if joining {
                    ProgressView()
                } else {
                    Text(ready ? "Join" : "Waiting for the host")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primary)
            .disabled(!ready || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || joining)
            .frame(minHeight: 44)
        }
        .padding(24)
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(theme.foreground)
    }

    private func pollReady() async {
        while !Task.isCancelled, session == nil, !ended {
            do {
                switch try await getStudioJoinStatus(token: guestToken, apiURL: apiURL) {
                case .ended:
                    ended = true
                    return
                case let .status(status):
                    ready = status.ready
                    if status.streamStatus == "ended" {
                        ended = true
                        return
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func join() async {
        joining = true
        defer { joining = false }
        do {
            session = try await joinStudioGuest(
                token: guestToken,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                guestId: UUID().uuidString,
                apiURL: apiURL
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
