import Foundation

/// Where the widget (and, for consistency, the app) get their `SharedUsageSnapshots`
/// from.
///
/// This is the mitigation for the gate M1 waiver: Tristan asked to implement the
/// whole project overnight before the sideload test (T1.2) has run, so it isn't yet
/// known whether the App Group sharing channel survives Sideloadly's re-signing with
/// a free Apple ID (see T1.1, `docs/INSTALL-IPHONE.md`, PLAN.md §7). If the eventual
/// gate verdict (T1.4) is negative, the fix is a **second conformance** of this
/// protocol — e.g. "the widget fetches the provider APIs itself" — swapped in at the
/// composition root, without touching any view. Do not build that second conformance
/// now; this file is only the seam.
public protocol SnapshotSource: Sendable {
    func loadSnapshots() -> Result<SharedUsageSnapshots, SnapshotStoreError>
}

/// The only conformance today: reads the App Group container written by the app via
/// `SnapshotStore`. Read-only, no network — matches AGENTS.md rule 8 ("widgets v1
/// sans réseau ni token").
public struct AppGroupSnapshotSource: SnapshotSource {
    private let store: SnapshotStore

    public init(store: SnapshotStore) {
        self.store = store
    }

    public init(containerURL: URL?) {
        self.store = SnapshotStore(containerURL: containerURL)
    }

    /// Production entry point: resolves the real App Group container for
    /// `AppGroup.identifier` (single source of truth, `AppGroup.swift` — PLAN.md §4,
    /// Sideloadly remaps this identifier at re-signing, so it's never hardcoded here).
    public init() {
        self.init(containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier))
    }

    public func loadSnapshots() -> Result<SharedUsageSnapshots, SnapshotStoreError> {
        store.read()
    }
}
