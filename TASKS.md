# TASKS.md — Limits

> Protocole : `C:\Git project\WORKFLOW.md`. **Réserver avant d'écrire** : passer la
> tâche à `🔒 in-progress — @<agent> — <date>`, committer (`claim: …`), travailler,
> puis `✅ done` + commit. Un agent ne relit jamais son propre code.
> Références : blueprint technique dans `PLAN.md`, règles dans `AGENTS.md`.

## Phase 0 — Bootstrap (Opus, séquentiel)

- ✅ done — **T0.1 Repo GitHub public + remote** — @claude-opus — 2026-07-29
  https://github.com/TristeTemps78/Limits (public, `main`, remote `origin`). Fixtures
  vérifiées anonymisées avant publication (aucun secret dans l'historique).
- ✅ done — **T0.2 Scaffold XcodeGen 3 targets** — @sonnet-a, relu @sonnet-b (GO) — 2026-07-29
  `project.yml` : app `com.caldf.limitsapp` (iOS 17), extension WidgetKit
  `com.caldf.limitsapp.widgets` embarquée (`embed: true, codeSign: false`), package local
  `LimitsCore` (iOS 17 + **macOS 13** — le support macOS force l'absence d'UI dans le
  package, vérifié gratuitement par `swift test`). Entitlements App Group
  `group.com.caldf.limitsapp` + `keychain-access-groups` déclarés **identiques** sur les
  deux targets (Sideloadly les remappe à la re-signature — sans eux T1.2 ne prouverait rien).
  `LimitsCore/Tests/.../FixtureLoader.swift` remonte depuis `#filePath` jusqu'à `fixtures/`
  (pas de symlink : dev Windows) — base des tests de M2.
- ✅ done — **T0.3 CI build.yml** — @sonnet-a, relu @sonnet-b (GO) — 2026-07-29
  Jobs `test` (`swift test --package-path LimitsCore`) + `ipa` (xcodegen → archive non
  signée → artefact `Limits-ipa`) + `release` sur tag `v*` (`gh release create`, aucune
  action tierce). Xcode **16.2** épinglé explicitement sur `macos-15`. Garde-fou : le job
  échoue si `Payload/Limits.app/PlugIns/LimitsWidgets.appex` est absent (échec silencieux
  classique = IPA valide mais aucun widget installable).
  CI verte sur `main` : run 30445925341 (`test` ✅ + `ipa` ✅).
  *Note : `on: push` reste volontairement sans filtre de branche — c'est ce qui permet à
  chaque agent de prouver son lot sur sa propre branche avant merge.*

## Phase M1 — Dérisquage **[GATE LEVÉ le 2026-07-29 — voir encadré]**

> **Décision de Tristan (2026-07-29, soir)** : « continue d'orchestrer le projet […] pour
> TOUT implémenter ». Le gate M1 d'`AGENTS.md` (« ne pas lancer M2 sans verdict ») est donc
> **levé sur instruction explicite**, T1.2 étant une action humaine impossible de nuit.
> Mitigation retenue par l'orchestrateur pour qu'un verdict négatif coûte peu :
> 1. l'accès aux données côté widget passe par une **abstraction** (`SnapshotSource`), pour
>    que la bascule « le widget fetch lui-même » reste un changement local ;
> 2. l'**écran de diagnostic de T1.1 est conservé dans l'app finale** (réglages) — c'est
>    l'IPA finale que Tristan sideloadera, pas celle de T1.1, donc le test de gate reste
>    faisable après coup.

- ✅ done — **T1.1 App+widget « hello » avec App Group** — @sonnet-b, relu @sonnet-a — 2026-07-29
  3 canaux testés **séparément** (UserDefaults suite / fichier du conteneur App Group /
  Keychain), chacun avec sa cause d'échec affichée dans l'app **et** dans le widget
  (`systemSmall` + `accessoryRectangular`). CI verte : run 30447596953.
  Décisions techniques à retenir :
  - **`kSecAttrAccessGroup` volontairement omis** : `$(AppIdentifierPrefix)` n'existe qu'au
    build et serait remappé par Sideloadly ; l'item va dans le premier groupe des
    `keychain-access-groups`, identique sur les deux cibles. Aucun préfixe en dur.
  - **`kSecAttrAccessibleAfterFirstUnlock`** obligatoire, sinon le widget d'écran verrouillé
    ne lit rien et on conclurait à tort « Keychain KO ».
  - **`SecTaskCreateFromSelf` inexploitable sur iOS** (compile pour macOS, absent du SDK
    iOS public) → impossible de lire à l'exécution l'App Group réellement accordé après
    re-signature. Abandonné plutôt que contourné.
  - **`UserDefaults(suiteName:)` ne renvoie pas `nil` sans entitlement** sur iOS : il crée un
    domaine isolé au process. Le signal fiable est la **comparaison du compteur** entre
    l'écran de l'app et le widget (le widget ne fait que lire → preuve cross-process réelle).
  - `WidgetKit` seul ne suffit pas : `import SwiftUI` est requis pour voir `Widget`/`WidgetBundle`.
- ⏳ **en attente de Tristan** — **T1.2 Test humain sideload** (~20 min)
  Suivre `docs/INSTALL-IPHONE.md` : installer Sideloadly, sideloader **l'IPA finale** (le
  diagnostic est conservé dans les réglages de l'app, cf. encadré ci-dessus).
  *Vérifier : app démarre ; widget posable (home + lock) ; le compteur affiché par le
  widget est bien celui écrit par l'app (preuve cross-process) ; ligne Keychain OK.*
  Grille de lecture des messages d'échec : `docs/INSTALL-IPHONE.md`.
- ✅ done — **T1.3 Capture des fixtures depuis le PC** — @claude-fable — 2026-07-29
  `scripts/capture-fixtures.ps1` exécuté : 4 fixtures réelles anonymisées dans
  `fixtures/` + `fixtures/capture-report.md` (headers validés, codes HTTP).
- ⏳ **bloqué par T1.2** — **T1.4 Verdict de gate** (Opus)
  Si App Group KO après re-signature : réessayer via AltStore ; si toujours KO, basculer
  l'architecture « widget fetch lui-même » (décision documentée ici et dans PLAN.md).
  La bascule est pré-cadrée : le widget lit à travers `SnapshotSource`, seul le
  fournisseur change.

## Phase M2 — Cœur (parallèle, worktrees `agent/<sonnet-X>/<tâche>`)

- 🔒 in-progress — **T2.1 LimitsCore : modèles + clients usage** — @sonnet-a — 2026-07-29
  (*à livrer en premier, débloque T2.3/T2.4*)
  `Models`, `ClaudeUsageClient`, `CodexUsageClient` (parsing tolérant multi-alias piloté
  par `fixtures/`), `PollingPolicy` (§6 PLAN.md), `SnapshotStore`. Points durs vérifiés
  sur fixtures : Claude → privilégier `limits[]`, pourcents 0-100, `resets_at` null si
  fenêtre inactive ; Codex → classifier les fenêtres par `limit_window_seconds` (jamais
  par position primary/secondary), `secondary_window` peut être null. *Accept : tests
  unitaires couvrant chaque fixture + cas 429/401/clé inconnue ; CI verte.*
  *Relecteur : Sonnet B.*
- 🔒 in-progress — **T2.2 OAuth Claude + Codex** — @sonnet-b — 2026-07-29
  `ClaudeOAuth` (PKCE, parse `code#state`, exchange, refresh), `CodexOAuth` (PKCE,
  refresh, account_id depuis JWT), `KeychainStore`, `LocalCallbackServer` (:1455).
  **Commencer par re-vérifier les flows dans les sources de claude-code / codex-rs**
  (§3 PLAN.md). *Accept : tests unitaires PKCE/parsing/état ; CI verte ; revue de la
  gestion d'erreurs.* *Relecteur : Sonnet A.*
- 🟢 libre — **T2.3 Widgets** (Sonnet C — après T2.1)
  `RingGauge`/`BarGauge`, familles systemSmall/Medium/Large + accessoryCircular/
  Rectangular/Inline, TimelineProvider sur snapshot, placeholders (non connecté, données
  périmées, reconnecter), comptes à rebours `Text(timerInterval:)`. *Accept : compile en
  CI ; previews alimentées par les fixtures.* *Relecteur : Sonnet D.*
- 🟢 libre — **T2.4 App UI** (Sonnet D — après T2.1)
  Onboarding/connexion par provider (champ code-paste Claude, bouton login Codex),
  dashboard (anneaux/barres, crédits Codex, « à jour il y a X min »), réglages (comptes,
  seuils, intervalle, style). *Accept : compile en CI ; états loading/erreur/vide
  traités.* *Relecteur : Sonnet C.*

## Phase M3 — Intégration (1 Sonnet + Opus, séquentiel)

- 🟢 libre — **T3.1 Fil complet arrière-plan**
  BGAppRefreshTask → fetch → snapshot → notifications locales (resets + seuils) →
  `WidgetCenter.reloadAllTimelines()` ; refresh proactif des tokens ; bandeau
  « reconnecter ». *Accept : CI verte + validation device par Tristan (widget se met à
  jour après une session Claude Code sur le PC ; notification reçue à un reset).*
  **Critère d'acceptation supplémentaire (dette explicite de T2.2)** : le `SingleFlight`
  livré en T2.2 **doit être câblé** ici, une instance par provider, de sorte qu'un refresh
  déclenché par l'app au premier plan et un refresh déclenché par la `BGAppRefreshTask` ne
  puissent jamais partir en parallèle. Deux refresh concurrents déclenchent
  `refresh_token_reused` côté OpenAI, qui est un échec **définitif** : l'utilisateur devrait
  se reconnecter à cause d'une course interne à l'app.
- 🟢 libre — **T3.2 Revue transverse** (agent n'ayant pas écrit T3.1)
  `/code-review` complet, chasse aux fuites de tokens dans les logs, erreurs réseau.

## Phase M4 — Finitions & release

- 🟢 libre — **T4.1 Icône, dark mode, localisation FR**
- 🟢 libre — **T4.2 README + docs/INSTALL-IPHONE.md finalisés** (captures d'écran)
- 🟢 libre — **T4.3 Release v1.0** (tag → IPA en Release GitHub) + clôture WORKFLOW
  (état actuel CLAUDE.md, libération projet dans `_ORCHESTRATION.md`, note vault)

## Critère global « tout marche » (checklist finale)

1. CI verte (tests + IPA) sur chaque push.
2. Login Claude **et** Codex réussis sur l'iPhone.
3. Dashboard = vraies fenêtres 5 h/hebdo + crédits Codex.
4. Widgets home + lock screen posés, corrects, compte à rebours qui défile.
5. Widget rafraîchi après une session Claude Code sur le PC (délai BGTask accepté).
6. Notification locale reçue à un reset de fenêtre.
7. J+7 : re-signature Sideloadly Wi-Fi OK, données conservées.
