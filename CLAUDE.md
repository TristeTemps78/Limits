# CLAUDE.md — Limits

@AGENTS.md

## Notes spécifiques Claude

- Réponds en français. Dates absolues.
- Avant d'écrire : réserver dans `TASKS.md` (protocole `C:\Git project\WORKFLOW.md`).
- Les builds passent par GitHub Actions (`gh run watch` / `gh run download` pour
  récupérer l'IPA) — jamais de tentative de build locale.

## État actuel (2026-07-30)

- **Phase : v1.0 complète, jamais exécutée sur un iPhone.** Nuit du 2026-07-29 au
  2026-07-30 (Opus orchestrateur + agents Sonnet) : Phase 0, M1, M2, M3, M4 livrées.
  **300 tests verts**, CI verte sur `main`, IPA en Release :
  https://github.com/TristeTemps78/Limits/releases/tag/v1.0
- **La prochaine étape est humaine et bloque tout le reste — T1.2** : sideloader l'IPA et
  faire le test de gate décrit dans `docs/INSTALL-IPHONE.md` §6 (grille de lecture des
  messages de diagnostic incluse). Le verdict T1.4 en dépend, et avec lui la validité de
  l'architecture « l'app écrit, le widget lit un snapshot ».
- **`docs/TEST-PLAN.md` (T4.4, 2026-07-30) est le protocole à dérouler** : 19 tests numérotés
  couvrant les 7 critères, en trois séances (A = J0 en main, B = arrière-plan à J+1, C =
  re-signature à J+7), avec une fiche de relevé à renvoyer. Le gate se joue en **A2 puis C2** :
  c'est la re-signature qui casse les App Groups, un A2 vert à J0 ne suffit pas au verdict.
  Deuxième point de rupture identifié à la rédaction : **A4, le login Codex** — le serveur de
  callback écoute dans l'app sur `:1455` alors que la page d'autorisation tourne dans un autre
  processus iOS ; ce chemin n'a jamais été vérifié ailleurs que sur macOS.
- **À relire en priorité** : T3.1 (fil arrière-plan) et l'audit final ont été écrits **et**
  relus par l'orchestrateur — la limite de dépenses mensuelle a coupé les sous-agents en
  pleine phase M3. C'est le « rédacteur = relecteur » qu'`AGENTS.md` interdit.
- **Corrections importantes apportées cette nuit, à ne pas défaire** :
  - `PLAN.md` §3 corrigé sur **7 divergences OAuth** vérifiées contre le binaire `claude`
    2.1.220 installé et le source `openai/codex` (`docs/oauth-verification-2026-07-29.md`).
    Trois d'entre elles rendaient le login Claude impossible.
  - La CI **choisit dynamiquement** un Xcode ayant réellement le SDK iOS : épingler la
    version ne suffit pas, une image de runner portait Xcode 16.2 sans la plateforme iOS.
  - `on: push` sans filtre de branche est **volontaire** : c'est ce qui permet à un agent
    de prouver son lot sur sa branche avant merge.
- Décisions actées : OAuth on-device (clone fidèle de Limits, pas de compagnon PC) ;
  repo public ; Sideloadly remplace la vidéo Cydia Impactor (obsolète) ; gate M1 levé sur
  instruction explicite de Tristan, avec mitigations (`SnapshotSource` + écran de
  diagnostic conservé dans l'app finale).
