# TASKS.md — Limits

> Protocole : `C:\Git project\WORKFLOW.md`. **Réserver avant d'écrire** : passer la
> tâche à `🔒 in-progress — @<agent> — <date>`, committer (`claim: …`), travailler,
> puis `✅ done` + commit. Un agent ne relit jamais son propre code.
> Références : blueprint technique dans `PLAN.md`, règles dans `AGENTS.md`.

## Phase 0 — Bootstrap (Opus, séquentiel)

- 🟢 libre — **T0.1 Repo GitHub public + remote**
  Créer le repo public (gh), pousser. *Accept : `git push` OK, repo visible.*
- 🟢 libre — **T0.2 Scaffold XcodeGen 3 targets**
  `project.yml` : app iOS 17+ `com.caldf.limitsapp`, extension WidgetKit, package
  `LimitsCore` (squelettes compilables minimaux). *Accept : `xcodegen generate` +
  `xcodebuild archive` passent en CI.*
- 🟢 libre — **T0.3 CI build.yml**
  Workflow §5.1 de PLAN.md : job test (swift test LimitsCore) + job ipa (archive non
  signée → artefact `Limits.ipa`) + Release sur tag. *Accept : artefact téléchargeable
  sur un push.*

## Phase M1 — Dérisquage **[GATE : ne pas lancer M2 sans verdict]**

- 🟢 libre — **T1.1 App+widget « hello » avec App Group** (Sonnet)
  L'app écrit une valeur horodatée dans le conteneur App Group + Keychain (access group
  partagé) ; le widget (systemSmall + accessoryRectangular) l'affiche. *Accept : CI
  verte, IPA artefact.*
- 🟢 libre — **T1.2 Test humain sideload** (Tristan, ~20 min)
  Suivre `docs/INSTALL-IPHONE.md` : installer Sideloadly, sideloader l'IPA T1.1.
  *Vérifier : app démarre ; widget posable (home + lock) ; le widget lit bien la valeur
  écrite par l'app (App Group survit à la re-signature) ; Keychain OK.*
- ✅ done — **T1.3 Capture des fixtures depuis le PC** — @claude-fable — 2026-07-29
  `scripts/capture-fixtures.ps1` exécuté : 4 fixtures réelles anonymisées dans
  `fixtures/` + `fixtures/capture-report.md` (headers validés, codes HTTP).
- 🟢 libre — **T1.4 Verdict de gate** (Opus)
  Si App Group KO après re-signature : réessayer via AltStore ; si toujours KO, basculer
  l'architecture « widget fetch lui-même » (décision documentée ici et dans PLAN.md).

## Phase M2 — Cœur (parallèle, worktrees `agent/<sonnet-X>/<tâche>`)

- 🟢 libre — **T2.1 LimitsCore : modèles + clients usage** (Sonnet A — *à livrer en
  premier, débloque T2.3/T2.4*)
  `Models`, `ClaudeUsageClient`, `CodexUsageClient` (parsing tolérant multi-alias piloté
  par `fixtures/`), `PollingPolicy` (§6 PLAN.md), `SnapshotStore`. Points durs vérifiés
  sur fixtures : Claude → privilégier `limits[]`, pourcents 0-100, `resets_at` null si
  fenêtre inactive ; Codex → classifier les fenêtres par `limit_window_seconds` (jamais
  par position primary/secondary), `secondary_window` peut être null. *Accept : tests
  unitaires couvrant chaque fixture + cas 429/401/clé inconnue ; CI verte.*
  *Relecteur : Sonnet B.*
- 🟢 libre — **T2.2 OAuth Claude + Codex** (Sonnet B)
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
