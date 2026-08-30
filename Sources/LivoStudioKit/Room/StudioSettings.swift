import SwiftUI

struct StudioSettingsSheet: View {
    @ObservedObject var model: StudioRoomModel
    @Environment(\.studioTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.audioDevices.isEmpty {
                    Section("Microphone") {
                        ForEach(model.audioDevices) { device in
                            deviceRow(device, selected: model.selectedAudioId)
                        }
                    }
                }
                if !model.videoDevices.isEmpty {
                    Section("Camera") {
                        ForEach(model.videoDevices) { device in
                            deviceRow(device, selected: model.selectedVideoId)
                        }
                    }
                }
                if model.audioDevices.isEmpty, model.videoDevices.isEmpty {
                    Text("No devices available")
                        .foregroundStyle(theme.secondary)
                }
            }
            .navigationTitle("Studio settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { model.refreshDevices() }
    }

    private func deviceRow(_ device: StudioMediaDevice, selected: String?) -> some View {
        Button {
            model.selectDevice(device)
        } label: {
            HStack {
                Text(device.name)
                Spacer()
                if device.id == selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.primary)
                }
            }
        }
        .foregroundStyle(theme.foreground)
        .accessibilityAddTraits(device.id == selected ? [.isSelected] : [])
    }
}
