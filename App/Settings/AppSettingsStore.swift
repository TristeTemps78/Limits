import Foundation
import Combine
import LimitsCore

/// User-configurable preferences: notification thresholds, refresh interval, gauge
/// style. Scheduling actual local notifications from these thresholds
/// (`UNUserNotificationCenter`, `Notifications.swift`/`RefreshManager.swift` in
/// PLAN.md §4) is **not** built by this lot — T2.4 only covers letting the user set
/// and persist the values; a later lot wires them into real notification scheduling.
/// See the T2.4 report for this scope call.
///
/// Backed by `UserDefaults(suiteName: AppGroup.identifier)` rather than `.standard`:
/// these are exactly the kind of values a future widget or background refresh task
/// (running in a different process) would also need to read, so storing them in the
/// App Group suite now avoids a migration later. Falls back to `.standard` if the
/// suite can't be opened (entitlement missing — same defensive pattern as T1.1's
/// `SharedDefaultsStore`), so Settings still works even if the App Group itself is
/// broken; only cross-process sharing would be lost in that case.
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var warningThresholdPercent: Double {
        didSet { defaults.set(warningThresholdPercent, forKey: Keys.warningThreshold) }
    }
    @Published var criticalThresholdPercent: Double {
        didSet { defaults.set(criticalThresholdPercent, forKey: Keys.criticalThreshold) }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshInterval) }
    }
    @Published var gaugeStyle: GaugeStyle {
        didSet { defaults.set(gaugeStyle.rawValue, forKey: Keys.gaugeStyle) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let warningThreshold = "settings.warningThresholdPercent"
        static let criticalThreshold = "settings.criticalThresholdPercent"
        static let refreshInterval = "settings.refreshIntervalMinutes"
        static let gaugeStyle = "settings.gaugeStyle"
    }

    init(defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.defaults = defaults
        self.warningThresholdPercent = defaults.object(forKey: Keys.warningThreshold) as? Double ?? 80
        self.criticalThresholdPercent = defaults.object(forKey: Keys.criticalThreshold) as? Double ?? 95
        // PollingPolicy.minimumScheduledInterval is 15 min — matches the default
        // shown here, though this value isn't wired into PollingPolicy itself yet
        // (that's a fixed constant; making it configurable is future work).
        self.refreshIntervalMinutes = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 15
        self.gaugeStyle = defaults.string(forKey: Keys.gaugeStyle).flatMap(GaugeStyle.init) ?? .ring
    }
}
