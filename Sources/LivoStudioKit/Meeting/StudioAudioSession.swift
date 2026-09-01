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
            options: [Self.bluetoothHandsFree, .defaultToSpeaker]
        )
    }

    /// Hands-free Bluetooth. iOS 26 renamed `allowBluetooth` → `allowBluetoothHFP`;
    /// CI still compiles against Xcode 16.4 / the iOS 18.5 SDK.
    private static var bluetoothHandsFree: AVAudioSession.CategoryOptions {
        #if compiler(>=6.2)
        .allowBluetoothHFP
        #else
        .allowBluetooth
        #endif
    }

    static func relinquish() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
