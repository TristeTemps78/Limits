# AGENTS.md — règles projet Limits (source de vérité, tous agents)

> Lu par Codex/Hermes directement, par Claude via `CLAUDE.md` (@AGENTS.md).
> Protocole inter-agents : `C:\Git project\WORKFLOW.md` (réservation TASKS.md,
> worktrees, verrou projet dans `_ORCHESTRATION.md` racine).

## Ce qu'on construit

App iOS (SwiftUI, iOS 17+) + extension WidgetKit affichant les limites d'usage Claude
Code et Codex. Blueprint technique complet : `PLAN.md`. Ordonnancement : `TASKS.md`.

## Règles d'ingénierie (spécifiques à ce projet)

1. **Personne n'a de Mac.** Ni Xcode, ni simulateur. La preuve d'un travail est la **CI
   GitHub Actions** (runner macOS). Ne jamais déclarer une tâche finie sans CI verte.
   La validation visuelle/device passe par Tristan (sideload de l'artefact IPA) — la
   demander explicitement, ne jamais la présumer.
2. **`project.yml` (XcodeGen) est la seule définition du projet.** Aucun `.xcodeproj`
   committé. Toute nouvelle source/target/entitlement passe par `project.yml`.
3. **Fixtures = vérité du parsing.** Tout décodeur de réponse API se développe contre
   `fixtures/*.json` (réponses réelles anonymisées) et a un test par fixture. Parsing
   **tolérant** : clé inconnue ignorée, jamais de crash. Pour régénérer les fixtures :
   `scripts/capture-fixtures.ps1` (PC de Tristan uniquement — il lit ses credentials
   locaux ; ne jamais l'exécuter en CI).
4. **Le maximum de logique dans `LimitsCore`** (package SwiftPM sans UI) : c'est la
   seule partie testable sans device. App et Widgets restent des couches fines.
5. **Aucun secret dans le repo** (repo public !). Les `client_id` OAuth sont publics —
   OK. Tokens, cookies, `account_id`, emails : jamais dans le code, les fixtures, les
   logs ni les messages de commit. Les fixtures sont anonymisées par le script ;
   vérifier avant tout commit qui les touche.
6. **Jamais de token dans les logs.** Pas de `print` d'objets réseau bruts. Les erreurs
   loggent le statut HTTP et l'endpoint, rien d'autre.
7. **Réseau : respecter `PollingPolicy`** (§6 de PLAN.md — anti-429). Aucun fetch hors
   de cette politique, y compris « juste pour tester ».
8. **Widgets v1 sans réseau ni token** : ils lisent le snapshot App Group, c'est tout.
9. Les valeurs sensibles au temps (header `anthropic-beta`, version du User-Agent
   claude-code, scopes) vivent dans `LimitsCore/ProviderConfig.swift` — un seul endroit
   à corriger quand un provider change quelque chose.

## Orchestration

- **Opus 5** = orchestrateur : découpe, merge, arbitrages, gate M1. Il ne code pas les
  lots, il les relit et les intègre.
- **Sonnet (high)** = exécutants, un lot = un agent = un worktree
  (`agent/<nom>/<tâche>`) dès que deux lots tournent en parallèle.
- **Rédacteur ≠ relecteur** : chaque lot est relu (`/code-review`) par l'agent désigné
  dans TASKS.md avant merge par Opus.
- Commits atomiques fréquents, messages `type: sujet` (`feat:`, `fix:`, `test:`,
  `claim:`, `docs:`). Push sur la branche du worktree, jamais de force-push.
- **Gate M1 bloquant** : tant que le sideload + App Group ne sont pas validés sur
  l'iPhone (T1.2), on ne lance pas M2.

## Fin de session (chaque agent, obligatoire)

`TASKS.md` à jour (✅/🔒 sincères), « État actuel » de `CLAUDE.md` mis à jour, commit,
push. Décision durable → note dans le vault (`C:\Obsidian\Cerveau`), jamais de push du
vault par un agent.
