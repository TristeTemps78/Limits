import Foundation
import Network
import LimitsCore

/// Minimal local HTTP server for Codex's OAuth callback
/// (`http://localhost:1455/auth/callback`, hard-coded on OpenAI's side — see
/// `docs/oauth-verification-2026-07-29.md`, Codex `redirect_uri` row). Claude never
/// needs this: it uses the manual "paste the code" flow (`ClaudeOAuth.parsePastedCode`).
///
/// Request-line parsing (`code`/`state` extraction) lives in
/// `LimitsCore.CodexCallbackParser` so it's covered by `swift test` — this file is
/// only the socket plumbing around it, which needs `NWListener` and can't run in CI
/// (rule 4, AGENTS.md: keep the App target thin).
///
/// **Port fallback**: `codex-rs` itself tries to cancel a competing local server on
/// `:1455` (a `GET /cancel` to a previous instance) before falling back to `:1457`
/// after ~2s of retries — that negotiation assumes multiple *Codex CLI* processes
/// coexisting, which doesn't really map onto a single iOS app process. Here we just
/// try `:1455` once, then `:1457` once if the first bind fails, and surface an
/// explicit, actionable error if both are taken — never a silent hang (per the T1.1
/// mission's explicit requirement).
public final class LocalCallbackServer {
    public enum ServerError: Error, LocalizedError {
        case portsUnavailable(tried: [UInt16])

        public var errorDescription: String? {
            switch self {
            case .portsUnavailable(let ports):
                let list = ports.map(String.init).joined(separator: ", ")
                return "Impossible d'ouvrir le serveur de connexion local (port(s) essayé(s) : \(list)). Une autre app utilise peut-être déjà ce port."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.caldf.limitsapp.local-callback-server")
    private var listener: NWListener?
    private var didComplete = false

    public init() {}

    /// Starts listening and calls `completion` exactly once, either with the parsed
    /// `code`/`state` from the first well-formed callback request, or with a
    /// `ServerError`. Stops the listener immediately after that — never lingers past
    /// its one job.
    ///
    /// `onBound` fires once, as soon as a listener is actually accepting connections
    /// — with **which** port it bound to, `:1455` or the `:1457` fallback. The
    /// authorize URL's `redirect_uri` must be built with that exact port: opening the
    /// browser against a hardcoded `:1455` while the server silently fell back to
    /// `:1457` would mean the redirect lands on a port nothing is listening on
    /// anymore. Callers should open the browser from `onBound`, not before.
    public func start(
        ports: [UInt16] = [1455, 1457],
        onBound: @escaping (UInt16) -> Void,
        completion: @escaping (Result<OAuthCallback, ServerError>) -> Void
    ) {
        queue.async { [weak self] in
            self?.didComplete = false
            self?.bind(remainingPorts: ports, tried: [], onBound: onBound, completion: completion)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
        }
    }

    private func bind(
        remainingPorts: [UInt16],
        tried: [UInt16],
        onBound: @escaping (UInt16) -> Void,
        completion: @escaping (Result<OAuthCallback, ServerError>) -> Void
    ) {
        guard let port = remainingPorts.first, let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(.portsUnavailable(tried: tried)))
            return
        }

        // Loopback only: the only client that will ever hit this is Safari/
        // ASWebAuthenticationSession on the *same* device following the OAuth
        // redirect to `localhost`. Restricting the interface both matches that intent
        // exactly and avoids asking for anything resembling the iOS "Local Network"
        // permission, which governs discovery of/connections to *other* devices, not
        // loopback.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback

        guard let newListener = try? NWListener(using: parameters, on: nwPort) else {
            bind(remainingPorts: Array(remainingPorts.dropFirst()), tried: tried + [port], onBound: onBound, completion: completion)
            return
        }

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                onBound(port)
            case .failed, .cancelled:
                guard !self.didComplete else { return }
                self.listener = nil
                self.bind(remainingPorts: Array(remainingPorts.dropFirst()), tried: tried + [port], onBound: onBound, completion: completion)
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection, completion: completion)
        }

        self.listener = newListener
        newListener.start(queue: queue)
    }

    private func handle(
        connection: NWConnection,
        completion: @escaping (Result<OAuthCallback, ServerError>) -> Void
    ) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            guard
                error == nil,
                let data,
                let requestLine = String(data: data, encoding: .utf8),
                let callback = CodexCallbackParser.parse(requestLine: requestLine)
            else {
                Self.respond(on: connection, success: false)
                return
            }

            Self.respond(on: connection, success: true)

            guard !self.didComplete else { return }
            self.didComplete = true
            self.listener?.cancel()
            self.listener = nil
            completion(.success(callback))
        }
    }

    private static func respond(on connection: NWConnection, success: Bool) {
        let body = success
            ? "<html><body>Connexion réussie, vous pouvez retourner dans l'app Limits.</body></html>"
            : "<html><body>Requête de callback invalide.</body></html>"
        let status = success ? "200 OK" : "400 Bad Request"
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
