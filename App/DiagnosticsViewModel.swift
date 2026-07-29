import Foundation
import Combine
import WidgetKit
import LimitsCore

/// Drives the T1.1 diagnostic screen: writes the three shared-data channels and
/// reports what comes back from each, independently. See `DiagnosticsView` for the
/// screen itself and `SharedChannelsFacade` in LimitsCore for the channel logic.
@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var readResults: [SharedChannel: DiagnosticResult<SharedPayload>] = [:]
    @Published private(set) var writeResults: [SharedChannel: DiagnosticResult<Void>] = [:]
    @Published private(set) var writeCount: Int = 0
    @Published private(set) var lastActionAt: Date?

    let appGroupIdentifier: String

    private let facade: SharedChannelsFacade

    init(facade: SharedChannelsFacade = SharedChannelsFacade()) {
        self.facade = facade
        self.appGroupIdentifier = facade.appGroupIdentifier
    }

    /// Called on launch: reads whatever is already there (to resume the counter
    /// across relaunches on the same device) and immediately writes once, so the
    /// three channels are always exercised without needing to press the button.
    func onAppear() {
        refreshReads()
        let existingMax = readResults.values.compactMap { result -> Int? in
            if case .ok(let payload) = result { return payload.writeCount }
            return nil
        }.max() ?? 0
        writeCount = existingMax
        writeNow()
    }

    /// Writes all three channels with an incremented counter, then re-reads them.
    /// This is the single action behind both the initial launch write and the
    /// "Écrire maintenant" button — same code path, so the screen behaves
    /// identically either way.
    func writeNow() {
        writeCount += 1
        writeResults = facade.writeAll(writeCount: writeCount)
        lastActionAt = Date()
        refreshReads()
    }

    func refreshReads() {
        readResults = facade.readAll()
    }

    /// Asks WidgetKit to refresh the widget's timeline immediately, instead of
    /// waiting for the next opportunistic system refresh — lets Tristan see the
    /// widget pick up a fresh write without leaving the app or waiting.
    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
