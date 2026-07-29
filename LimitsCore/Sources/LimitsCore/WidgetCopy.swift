import Foundation

/// Centralized display strings (rule 4, AGENTS.md: "le maximum de logique dans
/// `LimitsCore`" extends naturally to the vocabulary a thin view reads off a model —
/// two views should never independently invent slightly different wording for the same
/// state) and French, user-facing text for the widget's explicit placeholders.

extension ProviderKind {
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

extension LimitWindowKind {
    public var displayName: String {
        switch self {
        case .session: return "Session (5 h)"
        case .weekly: return "Hebdomadaire"
        case .unknown: return "Fenêtre"
        }
    }

    /// For contexts with almost no room (`accessoryInline`, `accessoryCircular`
    /// captions).
    public var shortLabel: String {
        switch self {
        case .session: return "5 h"
        case .weekly: return "hebdo"
        case .unknown: return "?"
        }
    }
}

extension SnapshotStoreError {
    /// Text for the widget's "App Group indisponible" placeholder family. Deliberately
    /// generic about *why* — no file paths, no raw error internals (rule 6, AGENTS.md:
    /// errors surface only what's needed to act, nothing that could leak internals).
    public var widgetDiagnosticMessage: String {
        switch self {
        case .containerUnavailable:
            return "App Group indisponible"
        case .fileNotFound:
            return "Aucune donnée pour l'instant"
        case .unsupportedSchemaVersion:
            return "Mets à jour l'app"
        case .corrupted:
            return "Données illisibles"
        case .encodingFailed:
            return "Erreur d'écriture"
        }
    }
}

extension SnapshotFreshnessLevel {
    /// `nil` for `.fresh` — no banner is shown at all in that case.
    public var widgetBannerMessage: String? {
        switch self {
        case .fresh: return nil
        case .aging: return "Données pas encore actualisées"
        case .stale: return "Données non rafraîchies depuis un moment"
        }
    }
}
