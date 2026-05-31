# CLAUDE.md — `CS378H-Master/lo-runtime`

**Audience for this document:** CC, at session start.

Orientation for a Claude-Code session working in this repo. Read this first, then `runtime-abi.md`, then the runbook you were handed for this session. This file is the standing context that holds across tasks; the runbook is the specific task.

## What this repo is

The runtime-skeleton mono-repo for the CS 378H compilers course at UT Austin, Fall 2026. Three parallel skeletons — Rust, Zig, and modern C++ — share a single C ABI. Student teams in the course's P3 project pick one skeleton, fill in the stubbed entry points (GC, string ops, type ops), and build a working LO runtime on top. The instructor pre-implements the parts that don't change between projects so students don't have to.

This repo is implementation only. Language and ABI design happen in the `planning` repo (`CS378H-Master/planning`), a separate repo; CC implements here.

## Roles

- **DC** — the instructor. Binding decider on the runtime ABI, repo structure, and what ships. Reviews CC's work at task/phase boundaries via PR, and hands CC the runbook for each session.
- **SC** — Strategic Claude. Drafts and revises the specs and runbooks that drive CC's work, and responds to CC's findings. Does not write code.
- **CC** — you. Execute the runbook DC handed you (under `runbooks/`). Don't change the ABI or scope without DC sign-off.

DC and SC don't talk to CC directly; coordination is through DC. When CC needs SC input (e.g., "the ABI is ambiguous on X"), surface it in PR notes or as a `TODO(SC):` in code, and DC routes it to SC. The same flag-don't-guess protocol applies any time a task is underspecified or a file doesn't fit the documented pattern.

## Authoritative documents in this repo

- `runtime-abi.md` — the shared ABI specification. Read it before writing any code. All three skeletons implement this contract; where the implementation conflicts with the spec, the spec wins.
- `README.md` — repo overview: the directory layout and how to pick and build a skeleton.
- `runbooks/` — CC execution specs. The current session's task is the runbook DC names in the kickoff; read it before starting. Runbooks use forward-walking pre/postcondition discipline — execute phase by phase, verifying each phase's postconditions before moving on.

The `planning` repo holds additional documents (the LO-3/LO-4 language references, the formal grammar, the course-level state ledger) that aren't required for runtime work; consult only if a task needs that context. CC doesn't have direct `planning` access — reference those docs by a `planning:` prefix (e.g., `planning:lo-3-reference.md`). The prefix is documentation-only; it resolves only where DC has copied a doc into this repo (as with `runtime-abi.md`).

## Workflow

- **Branch policy.** `main` is protected; direct pushes are blocked. Work on feature branches per phase, named `<task>/phase-<N>-<short-name>` (e.g., `ws2/phase-a-rust`). Each phase lands as one PR once its postconditions verify.
- **Commit etiquette.** Small, focused commits with descriptive messages — one concern per commit where possible (types separate from logic, and so on). Conventional-commit prefixes (`feat:`, `refactor:`, `test:`, `docs:`, `chore:`) are preferred but not required.
- **Pre-commit hooks.** Installed via `scripts/install-hooks.sh` and enforced on every commit:
  - Rust: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`.
  - Zig: `zig fmt --check`.
  - C++: `clang-format --dry-run --Werror`, `clang-tidy` against the project's checks.
  - Universal: trailing-whitespace check, secrets scan (gitleaks).
- **Push cadence.** Push at the end of each phase once postconditions verify locally; DC reviews each PR before merge.
- **Test runs.** Each phase's verification step names the test commands to run locally before pushing. Don't push code that doesn't pass its own verification.

## Notes-to-self at phase close

At the end of each phase, before opening the PR, drop a short note at `runbooks/notes/cc-<task>-phase<N>-notes.md` covering:

- **What got done.** Two or three sentences. The PR body covers the same ground; the notes file is the durable form.
- **What was deferred and why.** Anything in the phase's spec left incomplete, ambiguous, or punted to a later phase.
- **What the next phase should re-read or watch for.** Cross-phase dependencies, gotchas, decisions that pinned downstream choices.
- **Ambiguities surfaced for DC / SC.** Open questions worth a chat with SC; DC reads these between phases.

These notes are CC's mechanism for handing context across phase boundaries without relying on chat-session memory. Keep them brief but specific — letters to the next CC instance picking up the work. At task close, collect anything that needs SC into `runbooks/notes/for-sc-<task>-spec-deltas.md` for DC to route.

## Scope discipline

- CC implements what the runbook specifies. Mechanical decisions inside a step (variable names, helper functions, module organization within a phase's scope) are CC's call.
- Architectural decisions — anything that changes the ABI, the public function signatures, the cross-skeleton directory structure, or the shared test-corpus shape — require DC sign-off. Surface via PR notes or a paused phase; don't invent the spec.
- Code-quality decisions (idioms, lint configuration, comment style) are CC's call, within any per-language style notes the runbook gives.
- If the runbook is ambiguous or contradictory, halt and ask. The cost of asking is low; the cost of building the wrong thing across three skeletons is high.

## Conventions specific to this repo

- **Filename casing.** `kebab-case.md` for documentation; language-native conventions for code (`snake_case.rs` for Rust, `snake_case.zig` for Zig, `snake_case.cpp`/`.h` for C++). `CLAUDE.md` and `README.md` are the SOP-mandated exceptions.
- **Tests directory.** `tests/` at repo root is shared across all three skeletons — language-agnostic LO programs and their expected outputs. Each skeleton additionally has language-native unit tests under `<lang>/tests/` for direct ABI verification (LO programs aren't runnable until a student's compiler exists).
- **Cross-references in docs.** Within this repo, link by relative path (`../runtime-abi.md`). To `planning`-repo docs, use the `planning:` prefix (documentation-only, per the note above).
