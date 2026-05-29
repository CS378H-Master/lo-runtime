# Phase 0 notes — repo bootstrap

## What got done

Top-level scaffolding (`README.md`, `.gitignore`, `LICENSE` placeholder), the full
directory tree with `.gitkeep` placeholders (`rust/src`, `zig/src`, `cpp/src`,
`cpp/include`, `tests/lo_programs`, `tests/expected`, `runbooks/notes`), the
pre-commit hook installer at `scripts/install-hooks.sh`, and a build-only CI
workflow at `.github/workflows/ci.yml`. The hook installs and runs cleanly; a
trial commit exercised it.

## Toolchain environment (the Phase 0 hard prerequisite)

Built and verified up front. All four checks pass:
`cargo 1.87.0`, `zig 0.13.0`, `clang 19.1.7`, `cmake 4.3.2`, plus
`wasm32-unknown-unknown`, `clang-format 22.1.5`, `clang-tidy 22.1.0`,
`gitleaks 8.21.2`.

**Heads-up for DC — Homebrew is broken on this machine.** `/opt/homebrew` is not
writable by the user, so `brew install` fails and wants a `sudo chown -R` on the
Homebrew prefix. I did **not** run that (large, sudo-requiring system change, not
something to do unprompted). Instead I provisioned everything user-local without
sudo:

- `rustup target add wasm32-unknown-unknown`
- Zig 0.13.0: official tarball → `~/.local/zig-0.13.0`, symlinked to
  `~/.local/bin/zig`.
- cmake / clang-format / clang-tidy: `pip install` (miniconda), landed in
  `~/miniconda3/bin`.
- gitleaks: release binary → `~/.local/bin/gitleaks`.

This means the toolchain depends on `~/.local/bin`, `~/.cargo/bin`, and
`~/miniconda3/bin` being on PATH (they are, in this shell). If a future session or
CC instance can't find a tool, that's why — check PATH before re-installing. DC
may want to repair Homebrew properly at some point so the environment is less
bespoke.

## Platform note (matters for later phases)

This machine is **darwin/arm64**, not the ABI's reference `x86_64-linux`. Native
artifacts here are arm64 Mach-O, not ELF. This is fine for local dev/test — the
ABI's struct layouts are parameterized on pointer width (64-bit native vs 32-bit
wasm), not endianness or OS, and arm64 + x86_64 agree on all of it (LP64, same
struct packing). The cross-skeleton layout audit in Phase 4 should still hold
byte-for-byte. Just don't be surprised that `liblo_runtime.a` here is a `.a` of
arm64 objects; CI (ubuntu) covers the x86_64-linux path.

## Decisions / deviations

- **Zig pinned to 0.13.0** to match the runbook exactly (it is written against
  0.13; 0.14+ changed the `build.zig` API surface — `addStaticLibrary`/
  `addExecutable` now take a `root_module`). Phase 2 should stay on 0.13 unless DC
  wants to bump; if so, the build.zig will need the 0.14 module API.
- **Hook `find` precedence fixed.** The runbook's sketch
  `find cpp/src cpp/include -name '*.cpp' -o -name '*.h'` has a precedence bug —
  with the implicit `-print` it only lists `.h` files. I parenthesized the `-o`
  group and added an empty-list guard so the hook is correct and is a no-op before
  the C++ sources exist.
- **gitleaks mode.** Hook uses `gitleaks protect --staged` (scans staged changes)
  rather than the runbook's `gitleaks detect --source .` (scans whole tree/history)
  — `protect --staged` is the right mode for a pre-commit hook. Verified it runs.
- **LICENSE** left as a `TODO(DC): pick license` placeholder per step 0.1 (no
  LICENSE in the planning repo yet).
- **CI** written now rather than deferred, but each language job is guarded on the
  presence of its build file (`hashFiles`-style `[ -f ... ]` check) so the
  workflow is green on the Phase 0 PR and does progressively more as each skeleton
  lands. Phase 4 wires in the test + C-harness invocations.

## What the next phase (Phase 1, Rust) should watch for

- The reference-implementation burden starts here: Phases 2 and 3 mirror Phase 1,
  so get the module layout, type definitions, and the `StringObject` flexible-tail
  convention right and documented — the other two skeletons copy the shape.
- Decide `static mut` vs `OnceLock` for `LO_EMPTY_STRING` and the bump pointer, and
  record what tipped it (clippy on 2024-edition-ish toolchains is strict about
  `static mut` refs — `cargo 1.87` may warn/deny `static_mut_refs`). Watch for that
  lint specifically; it shapes the allocator and shadow-stack code.
- ABI exit codes are specified (§3.8 table). They aren't exercised in Phase 1 unit
  tests (stubs panic), but the provided abort paths (`lo_alloc` OOM = 137,
  `lo_read_int` = 110/111, `lo_read_bool` = 112) must use the right codes — those
  are *provided*, not stubbed.
- `lo_abort_null_receiver` (§3.8) is in the **provided** set per ABI §4.4 but is
  not called out in the Phase 1 step list (1.1–1.11). I plan to implement it in
  Phase 1 anyway (in `gc.rs`/a small `abort.rs`) since it's "provided"; flagging so
  DC knows it wasn't in the numbered steps.

## Ambiguities surfaced for DC / SC

- **`lo_abort_null_receiver` placement.** ABI §4.4 lists it as provided; the Phase
  1 module list (step 1.2) doesn't mention it. Implementing as provided. OK?
- The runbook's "Open items for DC / SC review" (heap size default, C++ WASM
  toolchain, Catch2 vs GoogleTest, fixture corpus, WASM trap uniformity, license)
  are noted; proceeding with runbook defaults and recording each choice in the
  relevant phase notes.
