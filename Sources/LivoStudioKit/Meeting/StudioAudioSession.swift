import AVFoundation

/// Configures the shared session so iOS treats Studio as an active audio app
/// (`UIBackgroundModes: audio`) and does not suspend the process a few seconds
/// after backgrounding. RealtimeKit / WebRTC owns `setActive`; we only set
/// category and mode so we do not fight `RTCAudioSession`.
enum StudioAudioSession {
    static func configure() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .videoChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
    }

    static func relinquish() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
