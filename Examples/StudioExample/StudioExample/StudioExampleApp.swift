import LivoStudioKit
import SwiftUI

@main
struct StudioExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var hostToken = ""
    @State private var guestToken = ""
    @State private var mode: Mode?

    private enum Mode: String, Identifiable {
        case host, guest
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("Host token from POST /studio/host-session", text: $hostToken)
                        .textInputAutocapitalization(.never)
                    Button("Open host studio") { mode = .host }
                        .disabled(hostToken.isEmpty)
                }
                Section("Guest") {
                    TextField("Guest token", text: $guestToken)
                        .textInputAutocapitalization(.never)
                    Button("Open guest studio") { mode = .guest }
                        .disabled(guestToken.isEmpty)
                }
                Section {
                    Text("Mint tokens on your backend with an `lk_` API key. Do not paste that key into this app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Livo Studio Example")
            .fullScreenCover(item: $mode) { selected in
                switch selected {
                case .host:
                    LivoHostStudioView(hostToken: hostToken)
                case .guest:
                    LivoGuestStudioView(guestToken: guestToken)
                }
            }
        }
    }
}
