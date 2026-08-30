import LivoStudioAPI
import SwiftUI

/// Partner host entry: redeem a single-use host token, then present the room.
public struct LivoHostStudioView: View {
    @Environment(\.studioTheme) private var theme
    private let hostToken: String
    private let apiURL: URL
    private let onEvent: ((StudioEvent) -> Void)?

    @State private var session: StudioSession?
    @State private var errorMessage: String?

    public init(
        hostToken: String,
        apiURL: URL = LivoAPIConfiguration.productionAPIURL,
        onEvent: ((StudioEvent) -> Void)? = nil
    ) {
        self.hostToken = hostToken
        self.apiURL = apiURL
        self.onEvent = onEvent
    }

    public var body: some View {
        Group {
            if let session {
                StudioRoomView(session: session, apiURL: apiURL, onEvent: onEvent)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await redeem() } }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.primary)
                }
                .padding()
                .safeAreaPadding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StudioSkeletonView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .studioTheme(theme)
        .task { await redeem() }
    }

    private func redeem() async {
        errorMessage = nil
        do {
            session = try await redeemStudioHost(token: hostToken, apiURL: apiURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
