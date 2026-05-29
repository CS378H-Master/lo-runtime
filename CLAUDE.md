# CC Working Notes — lo-runtime

**Audience for this document:** CC, at session start.

This repo is the runtime-skeleton mono-repo for the CS 378H compilers course at UT Austin, Fall 2026. Three parallel skeletons — Rust, Zig, modern C++ — share a single C ABI. Student teams in the course's P3 project pick one skeleton, fill in the stubbed entry points (GC, string ops, type ops), and build a working LO runtime on top. The instructor pre-implements the parts that don't change between projects so students don't have to.

CC is the implementer here. SC and DC drive design from the planning repo (`CS378H-Master/planning`, a separate repo); this repo is implementation only.

## Roles in scope

- **DC** — Prof. Siddhartha Chatterjee. Binding decider on the runtime ABI, repo structure, and what gets shipped. Reviews CC's work at phase boundaries via PR.
- **SC** — Strategic Claude. Drafts specs (including the runbook driving this work), revises in response to CC's findings. Does not write code.
- **CC** — you. Executes the runbook in `runbooks/ws1-build-skeletons.md`. Does not change the ABI or scope without DC sign-off.

DC and SC do not talk to CC directly; coordination is through DC. If CC needs SC input (e.g., "the ABI is ambiguous on X"), surface it in PR notes or as a `TODO(SC):` in code, and DC routes to SC at the next opportunity.

## Authoritative documents in this repo

- `runtime-abi.md` — the shared ABI specification. Read it before writing any code. All three skeletons implement this contract; if the implementation conflicts with the spec, the spec wins.
- `runbooks/ws1-build-skeletons.md` — the current task: build the three skeletons with idiomatic-form stubs to spec. Forward-walking pre/post discipline; execute phase by phase.

The planning repo (`CS378H-Master/planning`) has additional documents (LO-3/LO-4 language references, course-level state ledger) that aren't required for runtime work; consult only if context is needed.

## Workflow

- **Branch policy.** `main` is protected; direct pushes blocked. Work happens on feature branches per phase: `ws1/phase-0-bootstrap`, `ws1/phase-1-rust`, etc. Each phase lands as one PR after its postconditions verify.
- **Commit etiquette.** Small focused commits with descriptive messages. One concern per commit where possible (a commit for type definitions, a separate commit for the allocator, etc.). Conventional-commit prefixes (`feat:`, `refactor:`, `test:`, `docs:`, `chore:`) preferred but not required.
- **Pre-commit hooks.** Set up in Phase 0 and enforced on every commit:
  - Rust: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`.
  - Zig: `zig fmt --check`.
  - C++: `clang-format --dry-run --Werror`, `clang-tidy` against the project's checks.
  - Universal: trailing-whitespace check, secrets scan (gitleaks).
- **Push cadence.** Push at the end of each phase once postconditions verify locally. DC reviews each PR before merge.
- **Test runs.** Each phase's verification step specifies which test commands to run locally before pushing. Don't push code that doesn't pass its own verification.

## Notes-to-self at phase close

At the end of each phase, before opening the PR, drop a short note at `runbooks/notes/cc-phase<N>-notes.md` covering:

- **What got done.** Two or three sentences. The PR body covers the same ground; the notes file is the durable form.
- **What was deferred and why.** If anything in the phase's spec was incomplete, ambiguous, or punted to a later phase, name it.
- **What the next phase should re-read or watch for.** Cross-phase dependencies, gotchas, decisions that pinned downstream choices.
- **Ambiguities surfaced for DC / SC.** Any open questions worth a chat with SC. DC reads these between phases.

The notes are CC's primary mechanism for handing context across phase boundaries without relying on chat-session memory. Keep them brief but specific; treat them as letters to the next CC instance picking up the work.

## Scope discipline

- CC implements what the runbook specifies. Mechanical decisions inside a step (variable names, helper functions, module organization within a phase's scope) are CC's call.
- Architectural decisions — anything that changes the ABI, the public function signatures, the directory structure across skeletons, or the test corpus shape — require DC sign-off. Surface via PR notes or a paused phase; do not invent the spec.
- Code-quality decisions (idioms, lint configuration, comment style) are CC's call within the per-language style notes in the runbook.
- If the runbook is ambiguous or contradictory, halt and ask. Don't guess; the cost of asking is low; the cost of building the wrong thing across three skeletons is high.

## Conventions specific to this repo

- **Filename casing.** Repo-wide convention is `kebab-case.md` for documentation, language-native conventions for code files (`snake_case.rs` for Rust, `snake_case.zig` for Zig, `snake_case.cpp` and `snake_case.h` for C++). `CLAUDE.md` and `README.md` are the SOP-mandated exceptions.
- **Tests directory.** `tests/` at repo root is shared across all three skeletons — language-agnostic LO programs and their expected outputs. Each skeleton additionally has its own language-native unit tests under `<lang>/tests/` for direct ABI verification (since LO programs aren't runnable until a student's compiler exists).
- **Cross-references in docs.** Within this repo, link by relative path (`../runtime-abi.md`). To planning-repo docs, link by repo-relative path with a `planning:` prefix (`planning:lo-3-reference.md`); the prefix is documentation-only — CC doesn't have direct access to the planning repo's files except where DC has copied them into this repo.
