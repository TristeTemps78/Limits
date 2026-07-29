# Rapport de capture des fixtures

Capture du 2026-07-29 19:10 (locale). User-Agent Claude : `claude-code/2.1.220`.
Headers Claude : `anthropic-beta: oauth-2025-04-20`. Headers Codex : `ChatGPT-Account-ID` + `originator: codex_cli_rs`.

| Fixture | Statut | Endpoint |
|---|---|---|
| `claude-usage` | **200 OK** | https://api.anthropic.com/api/oauth/usage |
| `codex-usage` | **200 OK** | https://chatgpt.com/backend-api/wham/usage |
| `codex-credits` | **200 OK** | https://chatgpt.com/backend-api/wham/rate-limit-reset-credits |
| `codex-profile` | **200 OK** | https://chatgpt.com/backend-api/wham/profiles/me |

Valeurs sensibles remplacées par `REDACTED` (clés email/nom/compte/ids/tokens).
Régénération : `powershell -ExecutionPolicy Bypass -File scripts\capture-fixtures.ps1`.
