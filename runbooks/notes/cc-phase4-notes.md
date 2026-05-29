# Phase 4 notes — shared corpus + cross-skeleton verification

## What got done

- **LO program fixtures** (`tests/lo_programs/` + `tests/expected/`): three
  placeholders — `alloc_basic` (alloc + int output → `42`), `string_basic`
  (String output → `hello`), `class_basic` (class + method dispatch → `7`).
- **`tests/README.md`**: documents the corpus, the C harness, per-skeleton link
  notes, and the layout-audit witnesses.
- **C harness** (`tests/c_harness/main.c` + `run.sh`): a pure-C ABI link test.
- **CI** (`.github/workflows/ci.yml`): each language job now builds + runs its
  test suite; a new `cross_skeleton` job builds all three libs and runs the
  harness.

Final local verification — all green: Rust (build + wasm + 11 tests + clippy +
fmt), Zig (build + wasm + test + fmt), C++ (build + ctest + clang-format), and the
harness (rust/zig/cpp all link from C and print `42`).

## Cross-skeleton layout audit — result: no drift

The three skeletons agree byte-for-byte. Verified four ways (all encode the same
numbers): Rust `const _` asserts, Zig `comptime` asserts, C++ `static_assert`,
and a C-side `_Static_assert` in the harness — `sizeof(Object)==16`, string data
at offset 20, shadow-frame roots at offset 16 on 64-bit (12/16/8 on 32-bit). Plus
the empirical link test: a single C object file links against all three `.a`s and
runs identically. No layout fixes were needed — getting the offset-of-not-size-of
rule right in each skeleton (Phases 1–3) paid off here.

## C harness linking — the per-skeleton differences (worth knowing)

`run.sh` handles these; documented so they aren't a surprise:

- **Rust** staticlib links from C with **plain `cc`** on macOS, but on Linux needs
  the system libs rustc pulls in (`-lpthread -ldl -lm …`). `run.sh` queries them
  dynamically via `cargo rustc --lib -- --print native-static-libs` and passes
  them through, so it's correct on both platforms without hard-coding.
- **Zig** staticlib needs **nothing extra** — `std` uses raw syscalls (we never
  `linkLibC`), so `cc harness.o liblo_runtime.a` just works.
- **C++** staticlib must be linked with the **C++ driver** (`c++`/`$CXX`), not
  `cc`, so libstdc++/libc++ comes in (the impl uses `std::vector`/`std::string`/
  exceptions). The runbook's idealized `cc … -llo_runtime` command (§4.4
  verification) is too simple for the C++ skeleton — flagged for SC to update the
  runbook's verification snippet to use the C++ driver for cpp.
- Cosmetic only: macOS `ld` warns about a duplicate `-lSystem` (already in the
  native-static-libs list) and a newer-macOS-version object for Zig. Neither
  affects the result.

## Caveats / open items

- **LO fixture syntax is a placeholder (TODO(SC)).** I don't have the LO-3 grammar
  (`planning:lo-3-reference.md`) in this repo, so the `.lo` bodies are best-effort
  and prominently marked. The **expected outputs are the stable contract**;
  validate/rewrite the `.lo` syntax before any conformance harness consumes them.
  The full suite lives in the `lo-testing` repo (per the 2026-05-28 topology lock).
- **C++ has no WASM artifact**, so the WASM side of the cross-skeleton story
  covers Rust + Zig only until the C++/WASM toolchain (Emscripten vs wasm-clang)
  is chosen (Phase 3 open item). The native ABI link test covers all three.
- **CI is authored but unrun by CC.** I can't execute GitHub Actions locally;
  the workflow is written carefully and the commands mirror what passed locally
  on macOS. The one Linux-specific risk (Rust harness link flags) is handled by
  the dynamic `native-static-libs` query. Watch the first CI run on the PR.
- The harness only calls **provided** entry points (init, alloc, print, shutdown,
  and reads the descriptor/empty-string statics). It must never call a stubbed
  entry point — those `unimplemented!()` / `@panic` / `throw` and would abort.

## Runbook open items recap (for DC/SC, carried across phases)

1. `ShadowFrame` inline-array layout (ABI §3.3) vs runbook step 1.3 wording.
2. `lo_abort_null_receiver` as a provided entry point in every skeleton.
3. Per-language I/O backends differ (Rust + Zig on stdlib I/O, C++ on `<cstdio>`)
   — behavior identical; OK under the soft consistency goal?
4. C++/WASM toolchain choice (blocks a C++ `.wasm` target).
5. Catch2 vs GoogleTest for C++ (went with Catch2).
6. Runbook §4.4 verification command should use the C++ driver for the cpp lib.
7. LO fixture grammar validation (above).
8. Heap default 16 MiB; `LO_HEAP_SIZE` override — kept as the default.
9. Homebrew broken on the build box; toolchains provisioned user-local (Phase 0).

## State after WS-1

All four skeleton/corpus phases complete. Each skeleton builds native + (Rust/Zig)
WASM, ships idiomatic stubs for the team-implements set, and passes its native
tests. The shared corpus and the C harness are in place; the three agree on the
ABI byte-for-byte and are C-linkable. The instructor's eventual acceptance gate
(implement Cheney's semispace in each, all shared tests pass) is unblocked.
