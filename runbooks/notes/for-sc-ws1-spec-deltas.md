# For SC — WS-1 spec/runbook deltas from skeleton implementation

**Audience:** SC, routed by DC. **From:** CC. **Date:** 2026-05-29.

WS-1 is complete and merged: three runtime skeletons (Rust/Zig/C++) plus the
shared corpus and the cross-skeleton C harness, all CI-green. While executing
[`ws1-build-skeletons.md`](ws1-build-skeletons.md) against
[`../runtime-abi.md`](../runtime-abi.md), CC hit five points that are SC's to
resolve — each touches the runbook or the ABI spec, not just implementation. Full
context is in `cc-phase0-notes.md` … `cc-phase4-notes.md` in this directory; this
is the distilled, actionable set.

## 1. `ShadowFrame` layout — runbook contradicts the ABI (fix the runbook)

Runbook step 1.3 says to represent roots as `roots: *mut *mut Object` (a pointer
field). ABI §3.3 specifies an **inline** array `roots: [*mut Object; N]` laid out
after the header. These differ: a pointer field would not match the frames
codegen stack-allocates, and a team's GC would scan the wrong memory. CC
implemented the ABI's inline-array layout in all three skeletons (header
`{parent, num_roots}` + inline tail at `offset_of(roots)`).

**Ask:** update runbook step 1.3 to describe the inline-array layout (and the
offset-of-not-size-of convention — see item 5).

## 2. `lo_abort_null_receiver` is "provided" in the ABI but missing from the step lists

ABI §4.4 lists it in the *provided* set, but the Phase 1–3 numbered steps
(1.1–1.11, etc.) never mention it. CC implemented it as provided in every skeleton
(exit 102 / WASM trap, message per §3.8).

**Ask:** add it explicitly to the per-phase step lists so it isn't ambiguous for
future skeletons/teams.

## 3. Runbook §4.4 verification command is wrong for the C++ skeleton

The snippet `cc tests/c_harness/main.c -L<lang>/target -llo_runtime` works for
Rust/Zig but not C++ — the C++ static library needs the C++ driver (`c++`/`$CXX`)
to pull in the C++ standard library. The shipped harness
([`../tests/c_harness/run.sh`](../tests/c_harness/run.sh)) handles this per
skeleton.

**Ask:** correct the §4.4 verification snippet to link the C++ lib with the C++
driver.

## 4. LO fixture grammar needs SC validation (`TODO(SC)`)

The three placeholder programs in `tests/lo_programs/*.lo` use best-effort LO-3
surface syntax — CC does not have `lo-3-reference.md` in this repo, so the syntax
is unverified. The **expected outputs** (`tests/expected/*.out`) are the stable
contract; the `.lo` bodies need rewriting to grammar-correct LO before any
conformance harness consumes them. Markers are in those files and
[`../tests/README.md`](../tests/README.md).

**Ask:** validate/rewrite the `.lo` syntax (or hand off to the `lo-testing`
suite).

## 5. Decisions CC made on SC's "Open items for DC/SC review" — bless or adjust

CC proceeded with runbook defaults and recorded each; flagging so they can be
ratified in the spec:

- **Per-language I/O backends differ.** Rust and Zig use standard-library I/O
  (`std::io` / `std.io`), C++ uses `<cstdio>` — *not* libc as the runbook
  sketched for Rust/Zig. Reason: the Rust/Zig `libc`/`std.c` path does not
  portably expose the `stdin`/`stdout` `FILE*` globals, and `feof` semantics do
  not match `lo_eof` ("at EOF *without consuming*"). Observable behavior and all
  abort exit codes are identical across the three. This sits under the "soft
  consistency" goal — OK to keep?
- **Flexible-tail offset convention** (also relevant to item 1). String data
  starts at `offset_of(StringObject, data)` (= 20 on 64-bit), **not** `size_of`
  (= 24, which the runbook step 1.3 text implies) — `size_of` includes trailing
  padding and points past the inline bytes. All three skeletons plus the C
  harness encode this. Worth stating explicitly in the ABI/runbook.
- **Heap default** 16 MiB with `LO_HEAP_SIZE` override — kept as specified.
- **C++ test framework:** Catch2 (not GoogleTest), vendored single-header.
- **WASM stub traps:** Rust `unimplemented!()`, Zig `@panic`, C++ `throw` all
  become WASM traps; SC's open question on whether the harness needs a *uniform*
  "stub called" trap shape is still open — no unification implemented yet.

## Not for SC (DC's items, noted for completeness)

- **C++/WASM toolchain** choice (Emscripten vs wasm-clang) — no C++ `.wasm`
  target exists until it's picked. The C++ sources are WASM-ready via
  `#ifdef __wasm__` branches but untested.
- **Build-machine environment:** Homebrew is broken on the build box; toolchains
  were provisioned user-local (see `cc-phase0-notes.md`).
