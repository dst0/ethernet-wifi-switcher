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

## Durable Learning Capture

- Treat every resolved bug, regression, setup trap, operator mistake, failed experiment, and unexpected behavior as a learning opportunity, not only as a code change.
- Before or while fixing an issue, preserve the observable symptom and decisive evidence. Once understood, record the root cause rather than only the final patch.
- Record enough detail to make the learning reusable:
  - what went wrong and why;
  - which approaches were tried, including what worked, what did not work, and why;
  - any unexpected constraints, side effects, or environmental differences;
  - the correct path and how it was verified;
  - the regression test, prevention rule, cleanup, or reset procedure that prevents recurrence.
- Put durable guidance in the appropriate canonical repository document in the same change: use `AGENTS.md` for agent behavior, `README.md` for user or setup paths, and the canonical architecture or product documentation for design and runtime contracts.
- When a cross-session memory tool such as `memory_save` is available, save resolved bugs, architectural decisions, durable facts, and learned patterns so future sessions can retrieve them.
- Do not leave important learnings only in chat, temporary notes, commit history, or a pull-request discussion.
- If an issue exposes repeated agent friction, add the shortest durable instruction here that would have prevented it.
- Keep learning records safe: never store credentials, tokens, private keys, customer data, or sensitive payloads; sanitize examples and evidence.

## Mandatory Learning Log

- Maintain the repository-wide append-only journal at `docs/learnings.md`.
- Add an entry in the same change whenever work reveals a resolved bug or regression, failed or misleading experiment, unexpected behavior, setup or environment trap, non-obvious constraint, important workaround, or rejected approach with reusable rationale.
- Routine successful work does not need an entry unless it produces a reusable insight.
- Use the exact entry structure documented in `docs/learnings.md`. Include the task/context, observation or failure, evidence, approaches tried and their outcomes, root cause, resolution, verification, prevention or follow-up, and the reusable learning.
- Mark uncertainty honestly. If root cause or resolution is incomplete, record the entry as `Partial` or `Open` and state what evidence is still missing.
- Keep the journal append-only by default: do not delete or rewrite older entries merely to make the history cleaner.
- Exception for confirmed falsehoods: when authoritative evidence proves that an entry itself was fabricated, hallucinated, or factually false, correct or remove the false content so future agents do not reuse it.
- A confirmed-falsehood correction must never be silent. Mark the entry `Corrected` and add a dated correction note stating what was wrong, the authoritative evidence used, and what was changed. Do not repeat removed sensitive content.
- If the evidence is incomplete or disputed, do not rewrite the original entry; add a dated `Partial` or `Open` follow-up instead.
- Link relevant issues, commits, logs, or regression tests when safe and useful.
- Never place credentials, tokens, private keys, customer data, sensitive payloads, or unsanitized production evidence in the journal.

<!-- destinationworks-universal-agent-baseline:v1 -->
## Universal Delivery Baseline (v1)

These rules are the portable minimum for Destination Works repositories. Repository-specific instructions may strengthen them or name concrete commands, but must not silently weaken them.

### Evidence, scope, and decisions

- Read the repository instructions and relevant canonical docs before changing files. Check available cross-session memory when prior decisions or recurring failures may affect the work.
- While actively working, reread a repository-root `user_updates.md` at least once per minute when it exists. Treat new entries as user instructions, handle them before continuing, remove only entries that were fully handled, and never delete the file itself.
- Establish the live baseline before diagnosing or claiming completion. Prefer direct evidence from current code, tests, CI, deployed artifacts, or authenticated system state over comments, stale reports, or agent summaries.
- Preserve unrelated and user-owned changes. Use an isolated branch/worktree for broad work, stage intentionally, and never reset, clean, delete, or rewrite unrelated state to simplify a task.
- For non-trivial changes, compare 2-3 viable approaches and record the decisive tradeoffs. Proof-test material assumptions with a focused reproduction or authoritative source before committing to the design.
- Test scripted replacements and bulk mechanical edits on a disposable copy of one representative file before applying them broadly; inspect the result for collateral changes.
- Keep implementation, user/setup documentation, architecture/runtime contracts, and operator guidance synchronized in the same change.
- Store closed, well-compressible logs and temporary evidence with Brotli quality 6 when practical. Never compress an actively appended log as one stream: rotate or close it into chunks first, then compress each completed chunk. Use a format better suited to append, random access, or unsupported tooling when required, and record the reason for that exception.

### Durable learning capture

- Maintain `docs/learnings.md` as the repository-wide learning journal. Add an entry in the same work that reveals a material resolved bug/regression, failed or misleading experiment, unexpected behavior, setup/environment trap, non-obvious constraint, important workaround, or rejected approach with reusable rationale; routine successful work needs no entry.
- Record the task/context, observable symptom, sanitized decisive evidence, approaches tried and why each worked or failed, root cause or honest uncertainty, resolution, verification, prevention/follow-up, reusable rule, and safe references. Use `Resolved`, `Partial`, or `Open` status truthfully.
- Keep entries append-only by default. Correct prior understanding with a new linked entry rather than rewriting history.
- Exception: when authoritative evidence proves an existing statement was fabricated, hallucinated, or factually false, correct or remove the false content so it cannot mislead future work. Mark the entry `Corrected` and add a dated note stating what was wrong, the authoritative evidence, and what changed; never use this exception for disputed interpretation, ordinary staleness, or changed external conditions.
- Promote the shortest prevention rule into the appropriate canonical instructions, setup guide, architecture contract, or operator runbook in the same change. Do not leave durable knowledge only in chat, commit history, a PR, or the journal.
- Never record secrets, credentials, private keys, customer data, sensitive payloads, device codes, or unsanitized production evidence.

### Validation and test quality

- Discover and use the repository's canonical commands; do not invent shared command names where the project does not define them.
- Use a validation ladder: fast targeted feedback while iterating, the repository pre-commit gate before commit, and the full pre-push/release-relevant gate before push. If a named gate does not exist, run the closest repository-native equivalent and document the exact evidence.
- A hook is developer feedback, not the authoritative merge gate. CI must rerun required checks from a clean checkout.
- Never weaken, skip, or replace a failing check merely to make it green. Read the failure, fix the cause, rerun the narrowest relevant test, then rerun the containing gate.
- Validate generated artifacts against their source and canonical generator. Do not hand-edit generated output or accept drift.
- Tests must cover meaningful behavior, negative/error paths, and important boundaries. Coverage is a regression signal, not a reason to add vacuous line-fillers or bypass comments.
- For non-trivial or high-risk changes, obtain an independent adversarial review of assumptions, tests, failure handling, and rollback before publication.
- Process-timeout tests must prove that descendants and inherited pipes are gone, not merely that the direct child received a signal. When an external Unix `kill` command receives a negative process-group operand, terminate option parsing with `--` and cover the Linux path.
- For user-visible UI changes, exercise the changed path in the real browser or installed application after automated tests pass; record the nearest honest evidence if UI automation is unavailable.

### Git, pull requests, and CI enforcement

- Start from current remote truth, keep commits scoped and reviewable, and verify the exact staged diff before committing. Do not mix unrelated work into one PR.
- A local pass, push, or successful agent report is not proof that remote CI passed. Confirm the remote PR head SHA and every required check on that exact revision.
- Self-merge only when branch/ruleset protection actually enforces the required checks and they all pass. If protection is unavailable, checks cannot start, or the head changed after validation, leave the PR open for owner approval.
- CI workflows must use least-privilege permissions, pinned third-party actions, explicit timeouts/concurrency, and repository-owned validation commands.
- Self-hosted workflows must target verified organization runner labels, check prerequisites early, and prefer runner-local/preinstalled toolchains and caches over dynamic marketplace installers or billing-dependent artifact/cache services.
- Prove self-hosted readiness as the runner service account with its real non-interactive `HOME`, `PATH`, permissions, working directory, and any runner-managed persisted environment snapshot; an administrator's shell or manually constructed environment is not equivalent to a real workflow job.
- Prerequisite probes must exercise the concrete subcommands and capabilities the job invokes, not infer support only from a parent runtime's major version.
- Runner services must restart after unexpected failure and terminate the complete job process group; for systemd, use `Restart=on-failure` and `KillMode=control-group`. Bound build/test parallelism to the shared host's measured memory budget and provision recovery swap without treating swap as permission for unbounded concurrency.
- Run unrelated repository or organization runner services under distinct Unix service accounts so user-scoped signals and cleanup cannot cross repository boundaries. After a runner migration, disable superseded services and watchdogs immediately; never leave a deleted registration in an automatic restart loop.
- Containers that bind-mount a reusable self-hosted worktree must write generated files as the runner UID/GID, or normalize ownership before exit even on failure. Prove a subsequent clean checkout can remove prior outputs.
- Scope runner prerequisites to the job's actual contract: native test jobs must not require release-only cross-platform emulation, while every published platform must fail closed unless its build and execution prerequisites are verified.
- PR descriptions must explain why the change was needed, what changed, approaches rejected, exact validation, bugs found/fixed with regression evidence, learning-log entries, risk, and rollback.

### Security and supply chain

- Never store or expose credentials, tokens, private keys, customer data, sensitive payloads, device codes, or unsanitized production evidence in source, logs, fixtures, PRs, or learning records.
- Treat dependency lifecycle scripts, lockfile changes, generated code, binary downloads, workflow actions, and base images as reviewed supply-chain inputs. Pin immutable versions/digests where supported and fail on unreviewed drift.
- When JavaScript is used, prefer `.js` filenames and migrate `.mjs` references unless the user explicitly requires another extension.
- Run repository-appropriate dependency, secret, and static security checks before publication. Waive only a specific reviewed false positive with narrow evidence; never use broad exclusions that hide future findings.
- Security-sensitive configuration and deployment paths must fail closed when required identity, authorization, signing, backup, or runtime prerequisites are missing.

### Release and deployment integrity

- When the repository publishes a deployable artifact, build it once, identify it by immutable digest, and test the exact bytes that will be promoted on every published platform.
- Generate provenance/SBOM, scan, sign, and verify the same immutable artifact before promotion. Promote by digest without rebuilding.
- Separate immutable provenance tags from mutable environment pointers. Publish and verify evidence first, move the smallest mutable production pointer last, verify the live promoted state, and define an exact rollback to the previously recorded digest.
- Do not describe registry publication as runtime deployment. If no external runtime target and verification contract are configured, state that boundary and fail closed rather than claiming production delivery.
- Rehearse backup/restore and rollback through safe isolated commands that produce inspectable evidence; documentation-string checks alone are not operational proof.

<!-- /destinationworks-universal-agent-baseline:v1 -->
