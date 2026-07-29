# Limits — widgets iPhone pour les limites Claude Code & Codex

Clone open-source de [getlimits.app](https://getlimits.app/) : une app iOS (SwiftUI +
WidgetKit) qui affiche en widgets les fenêtres d'usage **Claude Code** (session 5 h,
hebdo) et **OpenAI Codex** (5 h, hebdo, crédits de reset), avec login OAuth natif et
tokens dans le Keychain. Construite **sans Mac ni compte développeur payant** :
IPA non signée produite par GitHub Actions, installée via Sideloadly.

- 📐 Blueprint technique : [PLAN.md](PLAN.md)
- ✅ Avancement / tâches : [TASKS.md](TASKS.md)
- 🤖 Règles agents : [AGENTS.md](AGENTS.md)
- 📱 Installation sur iPhone : [docs/INSTALL-IPHONE.md](docs/INSTALL-IPHONE.md)
- 🔍 Vérification des flows OAuth (valeur par valeur, avec sources) :
  [docs/oauth-verification-2026-07-29.md](docs/oauth-verification-2026-07-29.md)

## Ce qui fonctionne

| | |
|---|---|
| Login OAuth Claude (Pro/Max) | PKCE + flow « code à coller » |
| Login OAuth Codex (ChatGPT) | PKCE + serveur de callback local `:1455` (repli `:1457`) |
| Dashboard | fenêtres session/hebdo par provider, crédits, âge de la donnée |
| Widgets écran d'accueil | `systemSmall` / `Medium` / `Large`, jauges anneau ou barre |
| Widgets écran verrouillé | `accessoryCircular` / `Rectangular` / `Inline` |
| Rafraîchissement de fond | `BGAppRefreshTask` → snapshot → rechargement des timelines |
| Notifications locales | à chaque reset de fenêtre + franchissement de seuil (80 / 95 %, réglables) |

Pas de serveur, pas de télémétrie, pas de notification poussée (impossible en signature
gratuite — tout est programmé localement sur l'appareil).

## Architecture en trois phrases

`LimitsCore` est un package SwiftPM **sans UI** qui contient tout ce qui se décide :
parsing des réponses API, politique réseau anti-429, classification des erreurs OAuth,
sélection et formatage de ce qui s'affiche. L'app et l'extension widget sont des couches
minces au-dessus. C'est ce qui rend le projet testable : **personne sur ce projet n'a de
Mac**, donc la seule preuve qu'un comportement est correct est un test qui tourne en CI.

L'app écrit un snapshot JSON dans le conteneur du groupe d'app ; les widgets ne font que
le lire, sans réseau ni token. Les comptes à rebours utilisent `Text(timerInterval:)` et
`Text(date, style: .relative)`, rafraîchis nativement par le système : ils défilent sans
consommer le budget de rafraîchissement qu'iOS accorde aux widgets.

## Développement

```bash
swift test --package-path LimitsCore
```

C'est la seule commande utile localement. Le projet Xcode n'est pas versionné : il est
généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen) depuis `project.yml`, et la CI
produit l'IPA. Voir [AGENTS.md](AGENTS.md) pour les règles d'ingénierie, notamment le
fait que les fixtures réelles dans `fixtures/` sont la source de vérité du parsing.

⚠️ Projet personnel, non affilié à Anthropic ni OpenAI. Il lit des endpoints d'usage non
documentés avec vos propres tokens OAuth — zone grise ToS assumée, à vos risques.
