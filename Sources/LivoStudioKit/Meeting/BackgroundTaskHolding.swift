import Foundation
import UIKit

/// Ends a short background assertion. An unended task is a watchdog kill.
@MainActor
public protocol BackgroundTaskHolding: AnyObject {
    func begin(_ name: String, expirationHandler: @escaping () -> Void) -> UUID
    func end(_ id: UUID)
}

/// `UIApplication.beginBackgroundTask` wrapper so `StudioRoomModel` stays
/// testable without the shared application.
@MainActor
public final class UIApplicationBackgroundTaskHolder: BackgroundTaskHolding {
    private var tasks: [UUID: UIBackgroundTaskIdentifier] = [:]

    public init() {}

    public func begin(_ name: String, expirationHandler: @escaping () -> Void) -> UUID {
        let id = UUID()
        let task = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            expirationHandler()
            Task { @MainActor in
                self?.end(id)
            }
        }
        tasks[id] = task
        return id
    }

    public func end(_ id: UUID) {
        guard let task = tasks.removeValue(forKey: id) else { return }
        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}
