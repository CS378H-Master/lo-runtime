# Runbook WS-1 — Build LO Runtime Skeletons

**Audience for this document:** CC.

**Authoritative ABI:** `runtime-abi.md` (in this repo). The runbook references that spec extensively; when in doubt, the ABI wins.

**Workstream tracker:** WS-1 in `planning:state-ledger.md`. State after this runbook lands: all three skeletons compile cleanly, ship with idiomatic stubs in the team-implements set, and pass their respective language-native unit tests for the provided entry points.

**Output:** Three parallel runtime skeletons under `rust/`, `zig/`, `cpp/`, plus shared `tests/` infrastructure. Each skeleton is independently buildable and testable. The instructor's pre-semester acceptance test (described in `runtime-abi.md` §4.5) is the eventual gate: implement Cheney's semispace in each, all shared tests pass.

## Definition of done

The runbook is complete when all of the following hold:

- Each of `rust/`, `zig/`, `cpp/` contains a working language-native build (Cargo / `build.zig` / CMake) that produces a static library (native) and a WASM module.
- Each skeleton implements every "Provided (working out of the box)" entry point per `runtime-abi.md` §4.4 — type definitions, special class descriptors plus `LO_EMPTY_STRING`, `lo_runtime_init` / `lo_runtime_shutdown`, all `lo_print_*` and `lo_read_*` and `lo_println` and `lo_eof`, `lo_push_frame` and `lo_pop_frame`, a bump allocator backing `lo_alloc`, `lo_gc_write_barrier` as a bare-store no-op, and `lo_abort_null_receiver` (the provided null-receiver abort helper, §3.8 — exit 102 on native, trap on WASM).
- Each skeleton stubs every "Stubbed (team implements)" entry point with the correct C-ABI signature and an idiomatic-form body that aborts with a clear "not implemented" message when called — `unimplemented!()` for Rust, `@panic("not implemented")` for Zig, `throw std::runtime_error("not implemented")` for C++. The resulting trap/abort *shape* is language-native and deliberately **not** unified across skeletons: a stub only ever fires during skeleton development (a team replaces each stub before its feature is exercised), so it is not part of the conformance contract. The contract is the observable behavior and abort exit codes of the *provided* entry points (§4.4), not how an unimplemented stub fails. Revisit only if a future conformance harness needs to distinguish "stub not implemented" from a real runtime abort.
- Each skeleton has language-native unit tests under `<lang>/tests/` (or `<lang>/src/tests/` per language convention) that exercise the provided entry points directly via the C ABI. Tests cover: allocation returns zero-initialized memory; shadow-stack push/pop maintains the linked list correctly; print and read entry points round-trip; `LO_EMPTY_STRING` is a valid zero-length `StringObject` after `lo_runtime_init`.
- The shared `tests/lo_programs/` directory contains the LO program test fixtures (documented but not auto-runnable until a student's compiler exists). At least three placeholder LO programs covering basic allocation, basic string, and basic class scenarios are present, each with an `expected.out`.
- Pre-commit hooks are installed and pass cleanly across all three skeletons.
- A top-level `README.md` at the repo root walks readers from zero to "I picked a skeleton; here's how I build and test it."

## Phase 0 — Repo bootstrap

**Preconditions.** The `lo-runtime` repo exists with an initial commit (created by DC). `runtime-abi.md` is committed at repo root. `CLAUDE.md` is committed at repo root. This runbook is committed at `runbooks/ws1-build-skeletons.md`. The `main` branch is protected (the `scripts/hooks/pre-push` pattern from the planning repo applies here too — DC may have already committed equivalents).

**Toolchain environment (hard prerequisite — CC builds at Phase 0, DC fallback).** The local development environment must have all three language toolchains installed before any phase runs, not just before the phase that uses each: Rust (rustup, stable channel, plus `rustup target add wasm32-unknown-unknown`), Zig (stable channel, ~0.13 — verify against current release notes), and C++ (clang 18+ or gcc 14+, CMake 3.28+, plus `clang-format` and `clang-tidy` for the pre-commit hooks). The per-phase preconditions below restate the specific toolchain each phase needs, but the environment build is a single up-front task. C++ is more commonly preinstalled than Rust and Zig, but CMake 3.28+ and a recent clang are not guaranteed and should be verified. **Ownership (resolved 2026-05-29):** CC builds this environment as the first Phase 0 action. If CC's environment lacks the privileges to install toolchains (locked-down sandbox, no package-manager access), CC surfaces this immediately rather than working around it, and DC provisions the environment before CC proceeds. Either way the environment must exist and verify (`cargo --version`, `zig version`, `clang --version`, `cmake --version` all succeed) before Phase 0 scaffolding begins.

**Steps.**

0.1 — **Top-level scaffolding.** Create at repo root:
- `README.md` — repo overview matching `runtime-abi.md` §4.3's directory tree. One paragraph framing the repo, one paragraph per skeleton, one paragraph on the shared test corpus, and a "picking a skeleton" decision aid.
- `.gitignore` — entries for Rust (`/target`, `Cargo.lock` for libraries is fine to commit but `*.rs.bk` and other tooling noise are out), Zig (`zig-cache/`, `zig-out/`), C++ (`build/`, `*.o`, `*.a`, `compile_commands.json`), and platform noise (`.DS_Store`, `Thumbs.db`).
- `LICENSE` — copy whatever DC has chosen for course materials (likely the same as the planning repo's; if unclear, leave a `TODO(DC): pick license` and proceed).

0.2 — **Directory tree.** Create empty directories with `.gitkeep` placeholders:
- `rust/src/`
- `zig/src/`
- `cpp/src/`, `cpp/include/`
- `tests/lo_programs/`
- `tests/expected/`
- `runbooks/notes/`

0.3 — **Pre-commit hook setup.** Create `scripts/install-hooks.sh` that installs a `pre-commit` hook running all language formatters and linters available locally. The hook should skip languages whose toolchains aren't installed (no hard error if `zig` isn't on PATH on a Rust-only contributor's machine). Hook structure:
```
#!/usr/bin/env bash
set -e
command -v cargo >/dev/null && (cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings)
command -v zig >/dev/null && (cd zig && zig fmt --check src)
command -v clang-format >/dev/null && find cpp/src cpp/include -name '*.cpp' -o -name '*.h' | xargs clang-format --dry-run --Werror
command -v gitleaks >/dev/null && gitleaks detect --source . --no-banner
```

0.4 — **CI workflow** (optional in this phase; defer to Phase 4 if scoped tight). Set up a basic GitHub Actions workflow at `.github/workflows/ci.yml` that runs `cargo build`, `zig build`, and CMake build on push and PR. Don't gate on test pass yet (tests come in later phases); just build.

**Postconditions.** Repo has a valid directory structure, a working pre-commit hook on the developer's machine, and a top-level README that orients a reader. `git status` shows nothing untracked outside the gitignore set.

**Verification.** `bash scripts/install-hooks.sh` runs without error. A trial commit triggers the hook. `git ls-files | head` shows the expected top-level structure.

**Notes-to-self.** Drop `runbooks/notes/cc-phase0-notes.md` at phase close summarizing what landed and any TODOs that crossed into later phases.

## Phase 1 — Rust skeleton

**Preconditions.** Phase 0 complete. `rust/` directory exists with `.gitkeep`. Rust toolchain installed (rustup, stable channel). For WASM target: `rustup target add wasm32-unknown-unknown`.

**Steps.**

1.1 — **Cargo project.** Create `rust/Cargo.toml` and `rust/src/lib.rs`. Cargo.toml structure:
- `[package]` — name `lo_runtime`, version `0.1.0`, edition `2021`.
- `[lib]` — crate-type `["staticlib", "cdylib", "rlib"]`. The staticlib targets native linking; the cdylib targets WASM; the rlib lets the language-native tests link the library.
- `[dependencies]` — minimal, ideally empty. Native I/O uses `std::io`, not `libc` (see step 1.8 and `runtime-abi.md` §3.7), so no `libc` dependency is needed for I/O; add one only if a specific entry point genuinely requires a libc symbol. No GC libraries; the skeleton is hand-rolled.
- `[profile.release]` — `lto = "thin"`, `codegen-units = 1`. The runtime is small and statically linked; LTO matters.

1.2 — **Module structure.** `rust/src/lib.rs` declares the modules and re-exports the public C-ABI surface. Modules:
- `object` — type definitions for `Object`, `ClassDescriptor`, `ShadowFrame`, `VTableEntry`, `StringObject`.
- `descriptors` — `LO_STRING_CLASS`, `LO_INT_BOX_CLASS`, `LO_BOOL_BOX_CLASS` as `static` items; `LO_EMPTY_STRING` declared as `static mut` (or behind `OnceLock` if a safer pattern fits) initialized at runtime.
- `alloc` — bump allocator and `lo_alloc`.
- `shadow_stack` — `current_frame` static, `lo_push_frame`, `lo_pop_frame`.
- `init` — `lo_runtime_init`, `lo_runtime_shutdown`. Initializes the bump heap and `LO_EMPTY_STRING`.
- `io` — all `lo_print_*` and `lo_read_*` and `lo_println` and `lo_eof`.
- `string_ops` — stubs for `lo_string_new`, `lo_string_concat`, `lo_string_repeat`, `lo_string_compare`, `lo_string_reverse`.
- `cast` — stubs for `lo_cast_check` and `lo_instanceof`.
- `gc` — stub for `lo_gc_collect`; bare-store implementation of `lo_gc_write_barrier`.

`lib.rs` uses `pub use module::function` to re-export the public C-ABI surface so the crate consumer sees them at the top level.

1.3 — **Type definitions** (`object.rs`). All types match `runtime-abi.md` §2 byte-for-byte on 64-bit. Use `#[repr(C)]` on every struct and `#[repr(transparent)]` where applicable. Layout assumptions:
- `Object`: `class_descriptor: *const ClassDescriptor` (pointer-sized) + `gc_bits: u32` + `flags: u32`. Total 16 bytes on 64-bit.
- `ClassDescriptor`: per `runtime-abi.md` §2.1, all fields in declared order.
- `ShadowFrame`: per §3.3 — header `{ parent, num_roots }` followed by an **inline** `roots` array laid out immediately after the header (`roots: [*mut Object; N]` conceptually), *not* a pointer field. This matches the frames codegen stack-allocates; a pointer-field representation would make a team's GC scan the wrong memory. In Rust the flexible tail is awkward: emit the header struct with a zero-size `roots: [*mut Object; 0]` marker and have callers/GC index off `base + offset_of!(ShadowFrame, roots)` (see the offset-of convention below). Document the inline-array layout in module docs.
- `StringObject`: header + `length` + inline `data` tail. Use `#[repr(C)]` with a fixed `data: [u8; 0]` zero-size tail and document that the allocation includes additional space. **Readers index the inline bytes off `base + offset_of!(StringObject, data)`, not `base + size_of::<StringObject>()`** — `size_of` includes trailing alignment padding (24 on 64-bit) and points *past* where the inline bytes actually start (offset 20 on 64-bit). This offset-of-not-size-of rule applies to every flexible-tail type (`StringObject`, `ShadowFrame`); the C harness and all three skeletons encode it, and `runtime-abi.md` §3.2/§3.3 state it explicitly.

1.4 — **Static class descriptors and empty-string singleton** (`descriptors.rs`).
- `LO_STRING_CLASS`, `LO_INT_BOX_CLASS`, `LO_BOOL_BOX_CLASS`: each a `static ClassDescriptor` with `name` pointing at a `b"String\0"`-style byte string in `.rodata`, `parent` null, `vtable` empty (a static empty array), `pointer_offsets` empty. `instance_size` is `offset_of!(StringObject, data)` (the base before the inline tail, = 20 on 64-bit) for the String class — string allocations add `length` bytes to this base — and `mem::size_of::<Object>() + 4` (header + boxed int slot) for the int box, similarly for bool box. (Use `offset_of`, not `size_of`, for the String base — see step 1.3.)
- `LO_EMPTY_STRING`: `static mut LO_EMPTY_STRING: *mut Object = ptr::null_mut();` — initialized in `lo_runtime_init` via a bump-alloc of a zero-length `StringObject`. Marked `unsafe` for access; provide a safe getter behind `OnceLock` or equivalent if the pattern fits idiomatic modern Rust.

1.5 — **Allocation** (`alloc.rs`).
- Heap-backing storage: a `Vec<u8>` or a raw `mmap` region. Use `Vec<u8>` for simplicity; switch to `mmap` if 16 MiB on the stack becomes a concern.
- Default heap size: 16 MiB. Configurable via `LO_HEAP_SIZE` env var read at `lo_runtime_init`.
- Bump pointer: `static mut HEAP_START`, `HEAP_END`, `BUMP_PTR`. All accessed only via the public `lo_alloc` (and `lo_runtime_init` for setup).
- `lo_alloc(class)` implementation: round up `class.instance_size` to 8-byte alignment, check `BUMP_PTR + size <= HEAP_END`, write the `Object` header (class_descriptor field, zero gc_bits and flags), zero the rest of the allocation, advance `BUMP_PTR`. On overflow: abort (Phase 1 doesn't have GC; OOM is fatal).
- Document that codegen is responsible for post-allocation String-field initialization (`runtime-abi.md` §3.1).

1.6 — **Shadow stack** (`shadow_stack.rs`).
- `static mut CURRENT_FRAME: *mut ShadowFrame = ptr::null_mut();`
- `lo_push_frame(frame)`: set `frame.parent = CURRENT_FRAME`; `CURRENT_FRAME = frame`.
- `lo_pop_frame()`: `CURRENT_FRAME = (*CURRENT_FRAME).parent;` Assert non-null on entry (a defensive check on pop with no push is a programming error worth catching early in development).

1.7 — **Runtime initialization** (`init.rs`).
- `lo_runtime_init()`: allocate the heap region; initialize `BUMP_PTR = HEAP_START`; bump-allocate a zero-length `StringObject` for `LO_EMPTY_STRING` (class pointer set to `&LO_STRING_CLASS`, length 0); `CURRENT_FRAME = null`.
- `lo_runtime_shutdown()`: drop the heap (Vec drop suffices on native; no-op on WASM). The function exists for symmetry; not required to be called.
- `lo_abort_null_receiver()` (provided, per `runtime-abi.md` §3.8 and §4.4): print the null-receiver abort message to stderr and terminate — exit code 102 on native, `unreachable`/trap on WASM. This is a *provided* helper (codegen calls it on a null receiver before dispatch), not a stub; implement it, don't `unimplemented!()` it. Phases 2 (Zig) and 3 (C++) mirror this; the message text matches §3.8 verbatim across all three.

1.8 — **I/O** (`io.rs`). All four print functions and all four read functions, plus `lo_println` and `lo_eof`.
- On native (`cfg(not(target_arch = "wasm32"))`), use Rust `std::io` (a locked `stdout`/`stdin` handle), **not** raw `libc`. For `lo_print_string`, read `length` and the inline bytes (off `offset_of!(StringObject, data)`) and write them. Rationale and the offset-of rule are in `runtime-abi.md` §3.7 / §2.2.
- On WASM (`cfg(target_arch = "wasm32")`), declare imported host functions: `extern "C" { fn host_print_int(n: i32); fn host_read_int() -> i32; ... }` and forward to them. The host test harness wires the imports.
- `lo_read_string` on native: read up to the next newline from a buffered `stdin`, allocate a new `StringObject` via `lo_alloc(&LO_STRING_CLASS)` plus codepoint-aware sizing, copy bytes, return.
- `lo_read_int`: skip leading whitespace, parse an integer; abort on EOF or parse failure (status 111 / 110 per §3.7).
- `lo_read_bool`: read a whitespace-delimited token; accept `"true"` or `"false"`; abort (112) otherwise.
- `lo_eof`: must report end-of-input **without consuming** bytes — implement via a buffered reader's `fill_buf`/peek, **not** `feof` (which only reports EOF *after* a consumed read attempt and so does not satisfy the §3.7 semantics); WASM forwards to host.

1.9 — **Write barrier** (in `gc.rs`).
- `lo_gc_write_barrier(obj, offset, value)`: bare store, equivalent to `*((obj as *mut u8).add(offset) as *mut *mut Object) = value;`. Document at top of function that this is the non-generational implementation per `runtime-abi.md` §3.4; teams using a generational GC replace the body.

1.10 — **Stubbed entry points** (`gc.rs`, `string_ops.rs`, `cast.rs`).
- `lo_gc_collect()`: `unimplemented!("lo_gc_collect: team implements per P3")`.
- All five `lo_string_*`: `unimplemented!("lo_string_<name>: team implements per P3")`.
- `lo_cast_check`, `lo_instanceof`: `unimplemented!("lo_<name>: team implements per P3")`.
- Each stub has the full C-ABI signature with correct argument types and return type. The body compiles and (on call) panics with a recognizable message.

1.11 — **Language-native unit tests** (`rust/tests/abi_smoke.rs` and similar).
- `init_shutdown_clean`: `lo_runtime_init()`, then `lo_runtime_shutdown()`, no panic.
- `alloc_returns_zeroed`: allocate an `Object`, verify all bytes after the header are zero.
- `shadow_stack_push_pop`: push two frames, verify `current_frame` correctness, pop in reverse, verify back to null.
- `empty_string_singleton`: after init, `LO_EMPTY_STRING` is non-null, has class `&LO_STRING_CLASS`, length 0.
- `print_int_round_trips`: capture stdout (via test redirection), call `lo_print_int(42)`, verify `"42"` written.

The stubbed entry points are not directly tested — calling them panics by design. A "stub panics with expected message" test is acceptable for each but not required.

**Postconditions.** The Rust skeleton builds clean for native and WASM targets, all unit tests pass, `clippy` is silent.

**Verification.** Run from `rust/`:
```
cargo build
cargo build --target wasm32-unknown-unknown
cargo test
cargo clippy --all-targets -- -D warnings
cargo fmt --check
```

All five must succeed.

**Notes-to-self.** Drop `runbooks/notes/cc-phase1-notes.md`. Specific things worth noting: any choice between `static mut` vs `OnceLock` for `LO_EMPTY_STRING` (and what tipped the decision); any non-obvious unsafe-pattern that recurs; the `repr(C)` quirks you hit, if any, for the flexible-tail `StringObject` layout.

## Phase 2 — Zig skeleton

**Preconditions.** Phase 1 complete (Rust is the reference implementation; matching it across languages is the goal). Zig toolchain installed (stable channel; the runbook is written against Zig 0.13 or whichever stable was current when this lands — check the Zig release notes if the syntax surface has shifted).

**Steps.** Mirror Phase 1's module structure in Zig. Specific deviations from the Rust phase:

2.1 — **Build configuration.** `zig/build.zig` produces a static library (`liblo_runtime.a`) for native and a WASM module (`lo_runtime.wasm`) for `wasm32-freestanding`. Use `b.addStaticLibrary` for native and `b.addExecutable` with `wasm32-freestanding` for WASM. Export every public C-ABI function with `export fn` to ensure unmangled symbols.

2.2 — **Module structure.** Same conceptual files as Rust, with Zig naming: `object.zig`, `descriptors.zig`, `alloc.zig`, `shadow_stack.zig`, `init.zig`, `io.zig`, `string_ops.zig`, `cast.zig`, `gc.zig`. The root file is `src/lo_runtime.zig` (re-exports the C-ABI surface).

2.3 — **Type definitions.** Use `extern struct` for all ABI-visible types — Zig's `extern struct` matches C layout. Document the layout choice in the file's module-doc comment. Flexible-tail `StringObject` uses `data: [*]u8` with explicit pointer arithmetic, same convention as the Rust skeleton.

2.4 — **Static class descriptors and empty-string singleton.** `pub const LO_STRING_CLASS: ClassDescriptor = .{ ... };` for the class descriptors. `LO_EMPTY_STRING` is `pub var LO_EMPTY_STRING: ?*Object = null;` initialized in `lo_runtime_init`.

2.5 — **Allocation.** Same bump-allocator logic as Rust, using Zig's `[]u8` slice and pointer arithmetic. Heap region allocated via `std.heap.page_allocator` at `lo_runtime_init`.

2.6 through 2.11 — **Remaining steps parallel Phase 1.** Stub style: `@panic("not implemented")`. I/O on native uses `std.io` (a buffered `stdin` reader so `lo_eof` can peek without consuming, per §3.7), **not** `std.c`/libc; on WASM uses `extern "host" fn host_print_int(...)` declarations.

2.12 — **Language-native unit tests.** Zig's built-in test infrastructure (`test "init shutdown clean" { ... }`). Tests run via `zig build test`.

**Postconditions.** Zig skeleton builds clean for native and WASM, all unit tests pass, `zig fmt` is silent.

**Verification.** Run from `zig/`:
```
zig build
zig build -Dtarget=wasm32-freestanding
zig build test
zig fmt --check src
```

**Notes-to-self.** Drop `runbooks/notes/cc-phase2-notes.md`. Worth noting: Zig version pinning if any syntax surface differs from the runbook; any layout-compat verification against the Rust skeleton (the two should produce byte-identical Object headers on a given target).

## Phase 3 — C++ skeleton

**Preconditions.** Phases 1 and 2 complete. C++ toolchain installed — clang 18+ or gcc 14+; CMake 3.28+; `clang-format` and `clang-tidy` for the pre-commit hooks.

**Steps.** Mirror Phase 1's module structure in modern C++ (C++20 baseline; C++23 features where they help). Specific deviations:

3.1 — **Build configuration.** `cpp/CMakeLists.txt` produces a static library (`liblo_runtime.a`) for native and a separate target for WASM (use `EMSCRIPTEN` toolchain file if available; otherwise document the wasm-clang invocation). C++ standard set to C++20.

3.2 — **Module structure.** Headers in `cpp/include/lo_runtime/`, source in `cpp/src/`. Files mirror Rust: `object.h`, `descriptors.h`, `alloc.h` / `alloc.cpp`, `shadow_stack.h` / `shadow_stack.cpp`, `init.h` / `init.cpp`, `io.h` / `io.cpp`, `string_ops.h` / `string_ops.cpp`, `cast.h` / `cast.cpp`, `gc.h` / `gc.cpp`. A single umbrella header `lo_runtime.h` re-exports the C-ABI surface.

3.3 — **Type definitions** (`object.h`). All ABI-visible types are POD with `extern "C"` linkage for functions and `struct` layouts that match the ABI. Use `static_assert(sizeof(Object) == 16)` and similar to catch layout drift at compile time.

3.4 — **Static class descriptors and empty-string singleton.** `inline constexpr ClassDescriptor LO_STRING_CLASS = { ... };` for the class descriptors (the `inline` lets multiple translation units share the same instance without ODR violation). `LO_EMPTY_STRING` is a `Object* LO_EMPTY_STRING = nullptr;` initialized in `lo_runtime_init`.

3.5 — **Allocation.** Same bump-allocator logic, using `std::vector<std::uint8_t>` for the heap backing.

3.6 through 3.11 — **Remaining steps parallel Phase 1.** Stub style: `throw std::runtime_error("not implemented")`. I/O on native uses `<cstdio>`. On WASM, use `extern "C"` declarations that the host wires.

3.12 — **Language-native unit tests.** Use Catch2 or GoogleTest (DC's preference between the two — if no signal, default to Catch2 for header-only simplicity). Tests live under `cpp/tests/`. CMake build target `lo_runtime_tests`.

**Postconditions.** C++ skeleton builds clean for native (and WASM if the toolchain is locally available), all unit tests pass, `clang-format` and `clang-tidy` are silent.

**Verification.** Run from `cpp/`:
```
cmake -B build -S .
cmake --build build
ctest --test-dir build
clang-format --dry-run --Werror $(find src include -name '*.cpp' -o -name '*.h')
```

**Notes-to-self.** Drop `runbooks/notes/cc-phase3-notes.md`. Worth noting: Catch2-vs-GoogleTest decision if it came up; any C++20/23 feature you reached for; any layout-compat verification against Rust and Zig.

## Phase 4 — Shared test corpus + cross-skeleton verification

**Preconditions.** Phases 1, 2, 3 complete. All three skeletons build clean and pass their own language-native unit tests.

**Steps.**

4.1 — **Shared LO program test fixtures.** Populate `tests/lo_programs/` and `tests/expected/`. Initial set of three programs (these are not auto-runnable until a student's compiler exists; they're documented fixtures the eventual harness will exercise):
- `alloc_basic.lo` — allocates a small object and prints a known integer. `expected/alloc_basic.out` contains the integer.
- `string_basic.lo` — prints a known string literal. `expected/string_basic.out` contains the literal.
- `class_basic.lo` — declares one class with one method, instantiates, invokes, prints result. `expected/class_basic.out` contains the result.

LO program source is per the LO-3 grammar in the planning repo (`planning:lo-3-reference.md`). For this phase, the programs are placeholders — the goal is to establish the directory shape and conventions, not to be exhaustive.

4.2 — **Test-corpus README.** `tests/README.md` documents how the shared corpus is structured, what each program tests, and how the eventual harness will run them. Note explicitly that these tests are not auto-runnable until a student's compiler is in place — language-native tests in each skeleton's `<lang>/tests/` are what verifies the skeleton itself.

4.3 — **Cross-skeleton layout audit.** Verify by inspection that the three skeletons agree on:
- Object header byte layout (use the language-native `static_assert` / `comptime` / `const_assert` patterns where available).
- Class descriptor byte layout.
- Public C-ABI function signatures.

If any skeleton's layout differs, fix it; the ABI must be byte-identical across the three.

4.4 — **End-to-end smoke test.** Write a tiny C harness (in `tests/c_harness/`) that link-tests each skeleton: takes a static-library path, calls `lo_runtime_init`, allocates an `Object` via `lo_alloc`, prints something via `lo_print_int`, calls `lo_runtime_shutdown`. The harness verifies that the three skeletons are linkable from C code (not just from their own language) — this is the actual ABI promise.

4.5 — **CI workflow update.** Add the test invocations to `.github/workflows/ci.yml`: run unit tests for each skeleton, run the C harness against each.

**Postconditions.** Shared test corpus is in place, cross-skeleton layout agrees byte-for-byte, the C harness links and runs successfully against each skeleton, CI runs everything on push.

**Verification.**
```
# In each skeleton, build the static library, then link the C harness against it.
# Rust and Zig link with a C driver:
cc  tests/c_harness/main.c -L<lang>/target -llo_runtime -o /tmp/lo_test_<lang>
# The C++ skeleton must link with the C++ driver (c++ / $CXX) so the C++ standard
# library is pulled in — a plain `cc` link fails to resolve libstdc++/libc++ symbols:
c++ tests/c_harness/main.c -Lcpp/build -llo_runtime -o /tmp/lo_test_cpp
/tmp/lo_test_<lang>
```
`tests/c_harness/run.sh` is authoritative — it selects the right driver and the
per-skeleton native libs for you (Rust's reported `native-static-libs`, the C++
driver for the C++ lib); prefer running it over the snippet above.

**Notes-to-self.** Drop `runbooks/notes/cc-phase4-notes.md`. Note any layout drift you had to fix between skeletons; any conventions in the test corpus that DC may want to adjust.

## Style and idiom notes per language

**Rust.** Lean modern-idiom; `unsafe` is contained at the FFI boundary and the bump-allocator module. Prefer `OnceLock` and `Mutex` over `static mut` where the safety overhead is real (and absorb the small runtime cost). When `static mut` is unavoidable (the GC root list, the bump pointer), wrap access in `unsafe` blocks with a comment naming the invariant. Run `cargo clippy --all-targets -- -D warnings` and fix every lint.

**Zig.** Match Zig's preference for explicitness — no hidden allocations, explicit error returns where appropriate, no abuse of `comptime` for things that should be runtime. Use `extern struct` for ABI-visible types. The Zig idiom for "this is intentionally minimal until students extend it" is to write clear function-level doc comments naming the limitation; lean into that.

**C++.** Modern idioms — RAII for everything that owns, `std::string_view` for non-owning string parameters where it doesn't break the C ABI (i.e., for internal helpers, not the exported `lo_*` surface), `[[nodiscard]]` on return values that mustn't be silently dropped. The exported C ABI is C linkage (`extern "C"`); the implementation can use C++ freely. Avoid macros except for `static_assert` patterns and the unavoidable build-system integrations.

**Consistency across languages.** The three skeletons should be readable as parallel implementations — same module names (translated to language conventions), same function organization, same internal-helper structure where reasonable. A reader who has read the Rust skeleton should find the Zig and C++ skeletons predictable. This consistency is a soft goal; don't fight a language's grain to enforce it.

## Open items for DC / SC review

These are flagged by SC during runbook drafting as decisions that may want DC input rather than CC judgment. Surface in PR notes if relevant during execution; don't block on them otherwise.

- **Heap size default.** Runbook specifies 16 MiB, configurable via `LO_HEAP_SIZE`. Is this the right default? Should it be larger for the WASM target where allocation cost is higher? Asking SC if no signal from DC.
- **WASM toolchain for C++.** Runbook leaves the C++/WASM build path slightly open (Emscripten vs wasm-clang direct). DC may have a preference based on what the course assignments expect students to use.
- **Test framework for C++.** Catch2 vs GoogleTest. Runbook defaults to Catch2; flag for DC.
- **LO program test fixtures.** Three placeholders this phase. The full corpus (a dozen or two) is maintained as the conformance suite in the separate `lo-testing` repo (split out from the planning repo per the 2026-05-28 repository-topology lock). The skeleton's `tests/lo_programs/` may eventually merge with or mirror the `lo-testing` suite; that decision is downstream.
- **WASM trap semantics for stubs.** Rust's `unimplemented!()`, Zig's `@panic`, and C++'s `throw` produce different WASM trap shapes. Is uniformity needed across the three for the test harness to recognize a "stub called" trap? If so, document the unification convention.
- **License.** Runbook says "copy DC's choice from the planning repo." If the planning repo hasn't committed a LICENSE yet, this resolves there first.

These are not gating for CC; CC proceeds with the runbook's defaults and notes the choice in each phase's `cc-phase<N>-notes.md`. DC reviews the notes between phases and corrects course if needed.
