import Foundation
@testable import LimitsCore

/// Canned-response test double — no test in this target ever touches the network,
/// in CI or locally.
struct StubHTTPClient: HTTPClient {
    let result: Result<HTTPResponse, HTTPTransportError>

    func send(_ request: HTTPRequest) async -> Result<HTTPResponse, HTTPTransportError> {
        result
    }

    static func ok(_ body: Data, headers: [String: String] = [:]) -> StubHTTPClient {
        StubHTTPClient(result: .success(HTTPResponse(statusCode: 200, headers: headers, body: body)))
    }

    static func status(_ code: Int, headers: [String: String] = [:], body: Data = Data()) -> StubHTTPClient {
        StubHTTPClient(result: .success(HTTPResponse(statusCode: code, headers: headers, body: body)))
    }

    static func transportFailure(_ reason: String = "offline") -> StubHTTPClient {
        StubHTTPClient(result: .failure(HTTPTransportError(reason: reason)))
    }
}
