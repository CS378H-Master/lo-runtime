# For SC — WS-2 spec/runbook deltas from the Cheney collector build

**Audience:** SC, routed by DC. **From:** CC. **Date:** 2026-05-30.

WS-2 is implemented: the reference Cheney semispace collector lands in all three
skeletons (Rust reference in Phase A, Zig + C++ in Phase B), and all three pass
the cross-skeleton C harness with Cheney linked. While executing
[`ws2-cheney-collector.md`](../ws2-cheney-collector.md) against
[`../../runtime-abi.md`](../../runtime-abi.md), CC hit the points below that are
SC's to resolve (or to ratify). Full context is in
[`cc-ws2-phaseA-notes.md`](cc-ws2-phaseA-notes.md) and
[`cc-ws2-phaseB-notes.md`](cc-ws2-phaseB-notes.md).

## 1. `LO_EMPTY_STRING` symbol-meaning flip is atomic across skeletons + harness (the Phase A/B split doesn't model this)

Decision (A) makes `LO_EMPTY_STRING` a `.rodata` static *object* and changes the
**meaning of a shared ABI symbol**: WS-1 exported it as a pointer *variable*
(`Object *LO_EMPTY_STRING`), WS-2 as the object itself (`StringObject
LO_EMPTY_STRING`, referenced by address). The shared cross-skeleton harness
[`../../tests/c_harness/main.c`](../../tests/c_harness/main.c) consumes this
symbol, and the `cross_skeleton` CI job runs it against **all three** skeletons.

No single C declaration works for both models (pointer storage vs object storage
differ), so the flip is **atomic** across `main.c` + all three skeletons — it
cannot land in a Rust-only Phase A PR without reddening the `cross_skeleton` CI
job mid-transition. The runbook stages Phase A as "Rust only" and frames the
cross-skeleton harness as the post-both-phases gate (§4), which does not account
for this.

**DC decided (2026-05-30):** pull the *trivial* symbol flip (`.rodata` object +
test/header updates, **collectors still stubbed**) into Phase A for Zig and C++
as well, and flip `main.c`, keeping CI green throughout. The Cheney collectors for
Zig/C++ remained Phase B. This worked cleanly.

**Ask:** sharpen the runbook (and the §4 framing) to state that a change to the
*meaning* of a shared ABI symbol is atomic across the harness + all skeletons, so
it is exempt from the otherwise-Rust-only Phase A. This is the WS-2 analog of
WS-1 delta #1 (runbook-vs-ABI mismatch).

## 2. ABI text still describes `LO_EMPTY_STRING` as init-allocated (the cascade the runbook already flagged)

The runbook §2.5 "Cascade" and "Residual SC follow-up" note that `.rodata`
placement makes ABI **§2.3 and §3.6** stale where they describe `LO_EMPTY_STRING`
as allocated during `lo_runtime_init`, and that the symbol now denotes the
*object* (link-time-constant address; codegen embeds it with no load). CC found
§2.3 **already** carries the corrected object-reading wording (good); CC did not
edit the ABI. Re-surfaced here so the reconciliation isn't lost: confirm §3.6 and
the §4.4 "provided" list read consistently with the object reading. `TODO(SC)`.

## 3. `LO_HEAP_SIZE` minimum raised to `>= 2 * HEAP_ALIGN`

WS-1 accepted any `LO_HEAP_SIZE >= 16`. With two semispaces, a 16-byte total
gives 8-byte semispaces that cannot hold a single 16-byte header, so CC raised the
floor to `>= 32` (`2 * HEAP_ALIGN`) in all three skeletons; sub-floor or
unparseable values fall back to the 16 MiB default (unchanged WS-1 behavior). This
is a behavioral tweak to the decision-(B) mechanism, consistent across skeletons.

**Ask:** ratify the `>= 2 * HEAP_ALIGN` floor (or specify a different minimum).
The allocation-pressure tests set `LO_HEAP_SIZE`/heap-size well above it (4 KiB).

## 4. Allocation-pressure test uses a non-ABI explicit-size init hook in Zig/C++

A.4 test (v) needs a small heap to force collection deterministically. The Rust
reference does this via the `LO_HEAP_SIZE` env var (real init path). Zig and C++
instead use a non-ABI test hook (`heapInitWith` / `heap_init_with`) taking an
explicit total, because setting the C environment before the runtime's
`getenv`/`getEnvVarOwned` would require linking libc into the Zig test binary and
is racy across the test runners. The env-reading logic is identical across all
three; only the test injection differs. Behavior is identical — flagged only so
the soft-consistency ledger (WS-1 delta #5) records it.

## 5. WS-2 acceptance must wait on verified `.lo` fixtures (WS-1 delta #4, still open)

Per runbook §4, WS-2's "all three skeletons + Cheney pass the conformance suite"
is only a trustworthy signal once the shared `tests/lo_programs/*.lo` fixtures are
grammar-valid LO-3 (currently best-effort `TODO(SC)`; only `expected/*.out` is the
stable contract). This is SC / lo-testing work, restated from WS-1 delta #4. The
cross-skeleton **C harness** (`run.sh` / `main.c`) — the ABI link + behavior
witness — is green for all three with Cheney; the `.lo`-driven conformance layer
is the remaining piece.

## Not for SC (noted for completeness)

- **rustc lint drift.** CI's `stable` is rustc 1.96; its `unused_assignments`
  (`-D warnings`) flagged a root store that local 1.87 accepted. Fixed in Phase A
  by reading the root back. Not a spec issue — recorded so future skeleton work
  pins/refreshes the local toolchain against CI's `stable`.
- **C++ WASM / clang-tidy.** Unchanged from WS-1 (no C++ `.wasm` target picked;
  CI runs clang-format, not clang-tidy). Still DC's, per WS-1 notes.
