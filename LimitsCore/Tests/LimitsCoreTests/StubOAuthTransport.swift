import Foundation
@testable import LimitsCore

/// Test double for `OAuthTransport` — returns a fixed status/body (or throws a fixed
/// error) regardless of the request passed in. Lets tests exercise
/// `ClaudeOAuth.exchange`/`.refresh` and `CodexOAuth.exchange`/`.refresh` end to end —
/// including the `HTTPURLResponse` status branching and, for Codex, the failure
/// classifier wired *inside* `refresh` — without any real network call.
final class StubOAuthTransport: OAuthTransport {
    enum StubError: Error {
        case missingRequestURL
        case responseConstructionFailed
    }

    private enum Outcome {
        case respond(statusCode: Int, body: Data)
        case throwError(Error)
    }

    private let outcome: Outcome

    init(statusCode: Int, body: Data) {
        self.outcome = .respond(statusCode: statusCode, body: body)
    }

    init(throwing error: Error) {
        self.outcome = .throwError(error)
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        switch outcome {
        case .respond(let statusCode, let body):
            guard let url = request.url else {
                throw StubError.missingRequestURL
            }
            guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
                throw StubError.responseConstructionFailed
            }
            return (body, response)
        case .throwError(let error):
            throw error
        }
    }
}
