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

## Mandatory Learning Log

- Maintain the repository-wide append-only learning collection in `docs/leanings/`.
- Create exactly one Markdown file per learning in the same change whenever work reveals a resolved bug or regression, failed or misleading experiment, unexpected behavior, setup or environment trap, non-obvious constraint, important workaround, or rejected approach with reusable rationale.
- Routine successful work does not need an entry unless it produces a reusable insight.
- Follow the filename convention and exact entry structure documented in `docs/leanings/README.md`. Include the task/context, observation or failure, evidence, approaches tried and their outcomes, root cause, resolution, verification, prevention or follow-up, and the reusable learning.
- Mark uncertainty honestly. If root cause or resolution is incomplete, record the entry as `Partial` or `Open` and state what evidence is still missing.
- Keep learning files append-only by default: do not delete or rewrite older files merely to make the history cleaner. Put later discoveries in a new file that links the earlier learning.
- Exception for confirmed falsehoods: when authoritative evidence proves that an entry itself was fabricated, hallucinated, or factually false, correct or remove the false content so future agents do not reuse it.
- A confirmed-falsehood correction must never be silent. Mark the affected file `Corrected` and add a dated correction note stating what was wrong, the authoritative evidence used, and what was changed. Do not repeat removed sensitive content.
- If the evidence is incomplete or disputed, do not rewrite the original file; add a dated `Partial` or `Open` learning file that links it.
- Link relevant issues, commits, logs, or regression tests when safe and useful.
- Never place credentials, tokens, private keys, customer data, sensitive payloads, or unsanitized production evidence in learning files.
