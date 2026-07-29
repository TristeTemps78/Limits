import Foundation

/// Result of a read or write attempt on one shared-data channel (UserDefaults, file,
/// Keychain, ...). Deliberately not `Result<Value, Error>`: the failure case carries a
/// human-readable French string meant to be displayed as-is in the app and the widget
/// — T1.1's whole point is a diagnostic screen, not typed error handling.
public enum DiagnosticResult<Value> {
    case ok(Value)
    case failure(String)

    public var value: Value? {
        if case .ok(let value) = self { return value }
        return nil
    }

    public var failureReason: String? {
        if case .failure(let reason) = self { return reason }
        return nil
    }

    public var isOK: Bool {
        value != nil
    }
}

extension DiagnosticResult: Equatable where Value: Equatable {
    public static func == (lhs: DiagnosticResult<Value>, rhs: DiagnosticResult<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.ok(let l), .ok(let r)):
            return l == r
        case (.failure(let l), .failure(let r)):
            return l == r
        default:
            return false
        }
    }
}
