import Foundation

/// Time-sensitive provider values, all in one place (AGENTS.md rule 9): when
/// Anthropic bumps `anthropic-beta`, when Claude Code's own User-Agent format
/// changes, or when OpenAI moves an endpoint, this is the only file to touch.
///
/// OAuth-specific constants (client_id, authorize/token URLs, scopes) are **not**
/// here — they live in Sonnet B's T2.2 file. Kept deliberately separate so two
/// agents working in parallel worktrees don't edit the same file (see the T2.1 task
/// brief). This file only carries what the usage clients (`ClaudeUsageClient`,
/// `CodexUsageClient`) need.
public enum ProviderConfig {
    public enum Claude {
        public static let baseURL = URL(string: "https://api.anthropic.com")!
        public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

        /// PLAN.md §2.1: without this header the endpoint returns 401. Anthropic has
        /// changed this value before — that's exactly why it lives here and nowhere
        /// else.
        public static let anthropicBetaHeader = "oauth-2025-04-20"

        /// PLAN.md §2.1: without a `claude-code/…` User-Agent, requests land in an
        /// aggressively rate-limited bucket (near-permanent 429s). Version captured
        /// in `fixtures/capture-report.md` (2026-07-29). There is no discovery
        /// endpoint for "the current Claude Code version" — bump this by hand when
        /// it's known to be stale.
        public static let userAgent = "claude-code/2.1.220"
    }

    public enum Codex {
        public static let baseURL = URL(string: "https://chatgpt.com/backend-api")!
        public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        public static let resetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

        /// PLAN.md §2.2: identifies the caller as the Codex CLI, mirroring
        /// `codex-rs`. Required alongside `ChatGPT-Account-ID` on every request.
        public static let originator = "codex_cli_rs"

        /// PLAN.md §2.2 says the Codex User-Agent is free-form (unlike Claude's,
        /// which is load-bearing for rate limiting) — still centralized here so
        /// there's one place to change it if that ever stops being true.
        public static let userAgent = "Limits-iOS"
    }
}
