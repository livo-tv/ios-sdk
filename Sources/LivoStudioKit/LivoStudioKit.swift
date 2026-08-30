/// Livo native studio for iOS.
///
/// - `LivoHostStudioView(hostToken:)` / `LivoGuestStudioView(guestToken:)` for partners.
/// - `StudioRoomView(session:)` when the host app already minted a session
///   (first-party `POST /streams/:id/studio/session`).
///
/// Keep org API keys (`lk_…`) on the partner backend. Never embed them in the app binary.
@_exported import LivoStudioAPI
