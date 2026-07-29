import XCTest
@testable import LimitsCore

final class AppDashboardScreenStateTests: XCTestCase {
    func testIsEmptyWhenNeitherProviderIsConnected() {
        let state = AppDashboardScreenStateBuilder.build(
            claude: .notConnected,
            codex: .notConnected,
            lastSnapshotWriteSucceeded: true
        )
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(state.appGroupWarning)
    }

    func testIsNotEmptyWhenOneProviderIsConnected() {
        let state = AppDashboardScreenStateBuilder.build(
            claude: .loading,
            codex: .notConnected,
            lastSnapshotWriteSucceeded: true
        )
        XCTAssertFalse(state.isEmpty)
    }

    func testAppGroupWarningReflectsWriteFailure() {
        let state = AppDashboardScreenStateBuilder.build(
            claude: .loading,
            codex: .notConnected,
            lastSnapshotWriteSucceeded: false
        )
        XCTAssertTrue(state.appGroupWarning)
    }

    func testAppGroupWarningDoesNotHideProviderStates() {
        // The whole point of not having a blocking `.appGroupUnavailable` case: a
        // failed snapshot write must never erase what's otherwise a perfectly good
        // provider state.
        let state = AppDashboardScreenStateBuilder.build(
            claude: .loading,
            codex: .notConnected,
            lastSnapshotWriteSucceeded: false
        )
        XCTAssertEqual(state.claude, .loading)
        XCTAssertEqual(state.codex, .notConnected)
    }
}
