import Foundation

/// Minimal sync coordinator abstraction for the offline queue.
/// The `AppStore` currently drives sync directly; this type is the seam for a real implementation.
actor SyncEngine {
    func canSync(networkIsConnected: Bool) -> Bool {
        networkIsConnected
    }
}

