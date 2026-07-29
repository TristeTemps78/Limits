import Foundation

/// Partie **non graphique** de la présentation d'une sévérité : nom de symbole SF et mot
/// court. Ce sont des `String`, donc rien n'oblige à les dupliquer dans chaque cible UI.
///
/// Pourquoi ce fichier existe : l'app et l'extension widget avaient chacune leur
/// `SeverityStyle.swift` avec les **trois** membres (couleur, symbole, libellé) recopiés à
/// l'identique. La revue de T2.4 avait conclu « duplication inévitable, à garder
/// synchronisée » — c'est vrai pour la couleur (`SwiftUI.Color` ne peut pas descendre dans
/// `LimitsCore`, règle 4 d'AGENTS.md), mais **pas** pour les deux autres. Or c'est
/// justement le symbole et le mot qui portent l'information quand iOS écrase les couleurs
/// en rendu `accented`/`vibrant` sur l'écran verrouillé : les laisser dupliqués, c'était
/// accepter que la seule information survivant à l'écran verrouillé puisse diverger entre
/// l'app et le widget sans qu'aucun test ne le voie.
///
/// Il ne reste donc qu'un membre dupliqué au lieu de trois, et ces deux-là sont testés.
extension WindowSeverity {
    /// Symbole SF véhiculant la même urgence que la couleur, et **lisible sans elle**.
    public var symbolName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Mot court français, moitié textuelle de la redondance non chromatique — utilisé là
    /// où un symbole seul pourrait être ambigu aux tailles `accessory*`.
    public var shortLabel: String {
        switch self {
        case .normal: return "OK"
        case .warning: return "Attention"
        case .critical: return "Critique"
        case .unknown: return "?"
        }
    }
}
