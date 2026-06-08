# Agent Working Agreement

This file contains instructions for automated coding agents.

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
