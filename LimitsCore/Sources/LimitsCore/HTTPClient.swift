import Foundation

/// A minimal, provider-agnostic HTTP request — just enough for the usage clients.
public struct HTTPRequest: Equatable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]

    public init(url: URL, method: String = "GET", headers: [String: String] = [:]) {
        self.url = url
        self.method = method
        self.headers = headers
    }
}

/// A minimal HTTP response: status, headers (for `Retry-After`), and body bytes.
public struct HTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// Case-insensitive header lookup — HTTP header names aren't case-sensitive, but
    /// `URLResponse.allHeaderFields` and hand-built test doubles don't always agree
    /// on casing (`Retry-After` vs `retry-after`).
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Transport-level failure (no HTTP response at all — offline, DNS, TLS, timeout...).
/// Deliberately just a short reason string, never the request/response — rule 6 of
/// AGENTS.md: errors log the endpoint and status, nothing else that could carry a
/// token or account identifier.
public struct HTTPTransportError: Error, Equatable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

/// Injectable HTTP transport so the usage clients can be tested without ever
/// touching the network (required both in CI and locally — no dev machine here has
/// a simulator to fall back on either).
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async -> Result<HTTPResponse, HTTPTransportError>
}

/// Production implementation, backed by `URLSession`. Never logs the request or
/// response — callers only ever see the typed `HTTPResponse`/`HTTPTransportError`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async -> Result<HTTPResponse, HTTPTransportError> {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(HTTPTransportError(reason: "non-HTTP response"))
            }
            let headers = Dictionary(
                uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value -> (String, String)? in
                    guard let key = key as? String, let value = value as? String else { return nil }
                    return (key, value)
                }
            )
            return .success(HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: data))
        } catch {
            return .failure(HTTPTransportError(reason: error.localizedDescription))
        }
    }
}
