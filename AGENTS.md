# Agent Working Agreement

This file contains instructions for automated coding agents.

## User Updates

While actively working, reread `user-updates.md` for new instructions at least once per minute and incorporate any new guidance before continuing.

## Test Quality & Adversarial Review

- Tests must never be added solely as mechanical line-fillers to pass coverage gates. Tests must meaningfully verify domain logic, invariant preservation, realistic crash recovery, positive cases, negative cases, and edge cases.
- Bug fixes must start with a reproducible failing regression test before writing the fix.
- For non-trivial features, bug fixes, or test additions, automatically spawn an adversarial test-critic subagent to review the tests. The critic must evaluate whether the suite verifies real behavior vs artificial line coverage, identifies missing edge cases, and flags fragile/vacuous tests before work is completed.
- Never use coverage bypass comments (e.g. `/* v8 ignore */`, `#[cfg(not(coverage))]`, `# pragma: no cover`) to bypass coverage gates. All code in the repository must be reachable and exercised by tests; dead or unreachable code must be deleted rather than kept or suppressed (except rare compiler/type-exhaustiveness edge cases where a branch is syntactically required but provably unreachable at runtime).
- If you create or modify a test file, run it and iterate on test or implementation until it passes.

## Refactoring Guidelines (LSP/MCP)

Before executing any semantic refactoring (TypeScript/JavaScript, HTML, Rust), the agent must:
1. Run diagnostics for the target file/project to verify baseline state.
2. Use symbol tools (`definition`, `references`, `hover`, `workspace symbols`) to explore impact.
3. Prefer LSP rename/code-action tools over manual text/regex edits wherever possible.
   - For TS/JS: Use `ts-js-lsp` (`typescript-language-server`).
   - For HTML: Use `html-lsp` (`vscode-html-language-server`).
   - For Rust: Use `rust-lsp` (`rust-analyzer`) and/or `rust-analyzer-native` (`rust-analyzer-mcp`).
4. After making edits, run compiler/validation checks:
   - TS/JS: `npm test`, `npm run typecheck`, `npm run lint` (if available).
   - Rust: `cargo fmt`, `cargo clippy`, `cargo test`.
5. Never perform large cross-module or architectural refactors without creating a plan first.
