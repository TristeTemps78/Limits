# CLAUDE.md — Limits

@AGENTS.md

## Notes spécifiques Claude

- Réponds en français. Dates absolues.
- Avant d'écrire : réserver dans `TASKS.md` (protocole `C:\Git project\WORKFLOW.md`).
- Les builds passent par GitHub Actions (`gh run watch` / `gh run download` pour
  récupérer l'IPA) — jamais de tentative de build locale.

## État actuel (2026-07-29)

- **Phase : pack d'orchestration livré, code non commencé.** Session Fable du
  2026-07-29 : reverse engineering de getlimits.app, vérification des endpoints et des
  flows OAuth, blueprint (`PLAN.md`), tâches (`TASKS.md`), guide iPhone
  (`docs/INSTALL-IPHONE.md`).
- **T1.3 déjà ✅** : `scripts/capture-fixtures.ps1` exécuté sur le PC — fixtures réelles
  anonymisées dans `fixtures/`, rapport dans `fixtures/capture-report.md`.
- Prochaine étape : **Phase 0** (T0.1 repo GitHub public → T0.2 scaffold XcodeGen →
  T0.3 CI), puis gate M1.
- Décisions actées : OAuth on-device (clone fidèle de Limits, pas de compagnon PC) ;
  repo public ; Sideloadly remplace la vidéo Cydia Impactor (obsolète).
