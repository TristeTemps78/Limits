import XCTest
@testable import LimitsCore

final class AppOnboardingConnectionStateTests: XCTestCase {
    func testCanStartNewAttemptFromRestStates() {
        XCTAssertTrue(AppOnboardingConnectionState.notConnected.canStartNewAttempt)
        XCTAssertTrue(AppOnboardingConnectionState.connected.canStartNewAttempt)
        XCTAssertTrue(AppOnboardingConnectionState.failed(message: "x").canStartNewAttempt)
    }

    func testCannotStartNewAttemptWhileInFlight() {
        XCTAssertFalse(AppOnboardingConnectionState.connecting.canStartNewAttempt)
        XCTAssertFalse(AppOnboardingConnectionState.exchangingToken.canStartNewAttempt)
    }
}
