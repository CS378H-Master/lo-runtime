# WS-2 — Reference Cheney semispace collector

**Audience for this document:** CC, executing in `lo-runtime`. Routed by DC; SC authored.

This runbook specifies the instructor's reference implementation of Cheney's semispace copying collector — the canonical default on the P3 GC menu. It is the gate on WS-2: once Cheney exists in each skeleton, WS-2 runs all three skeletons + Cheney through the `lo-testing` conformance suite via the WS-1 cross-skeleton C harness. The collector is implemented against the GC hooks already specified in `runtime-abi.md` (read it first; where this runbook and the ABI conflict, the ABI wins and the conflict is a `TODO(SC)`).

One collector, three skeletons. The algorithm in §2 is language-agnostic; CC implements the same design in `rust/src/gc.rs`, `zig/src/gc.zig`, and `cpp/src/gc.cpp`, plus the `lo_alloc` OOM-path wiring in each `alloc.*`. The three are expected to produce identical observable behavior on the shared corpus — that identity is what WS-2 verifies.

---

## 1. Scope and contract

**In scope.** A complete, correct Cheney two-space copying collector behind the existing `lo_gc_collect` entry point, plus the `lo_alloc` OOM-path change that triggers it. Implemented in all three skeletons.

**Out of scope.** The other two menu collectors (mark-compact, generational) — students implement those in P3; the reference baseline is Cheney only. The write barrier (`lo_gc_write_barrier`) is **not** touched: Cheney is non-generational, so the ABI's provided bare-store implementation is already correct (ABI §3.4). CC confirms it remains a bare store and does not modify it.

**The contract CC must satisfy.** After implementation, each skeleton with Cheney linked in:

1. Passes its own language-native unit tests (WS-1 Phase-style), extended with the GC tests in §3.
2. Survives a forced `lo_gc_collect()` with live roots: reachable objects are preserved with updated addresses; unreachable objects are reclaimed; the shadow-stack roots and all interior pointer fields are rewritten to the objects' new locations.
3. Survives allocation pressure: a program that allocates past one semispace's capacity triggers collection through the `lo_alloc` OOM path, reclaims dead objects, and continues; only a genuine live-set overflow aborts, via the existing OOM contract (ABI §3.1: `lo_alloc: out of memory`, exit 137 native / `unreachable` trap WASM).
4. Leaves `LO_EMPTY_STRING` and any other immortal object neither moved nor collected (see §2.5).

---

## 2. Algorithm specification

### 2.1 Heap layout

Partition the managed heap into two equal-size semispaces, *from-space* and *to-space*. Exactly one is active at a time. A bump pointer `free` marks the next allocation address in the active (from-)space; `limit` marks its end. Allocation is `free += size; return old free` when it fits, collection-then-retry when it does not.

The total heap size uses the existing WS-1 mechanism (decision (5c)): a **16 MiB compile-time default, overridable at runtime via the `LO_HEAP_SIZE` environment variable read at `lo_runtime_init`**; each semispace is half of the total. Setting `LO_HEAP_SIZE` small lets the allocation-pressure tests (§3) force a collection deterministically. The provided skeletons currently back `lo_alloc` with a single bump region (WS-1); restructuring that region into two equal halves is part of this work.

### 2.2 Object size

The collector must compute an object's true byte size to copy it. Every LO-3/LO-4 object is fixed-size at `class.instance_size` **except** `String`, whose inline UTF-8 tail makes it variable-size (ABI §2.2):

```
size(obj):
    class = obj.class_descriptor
    if class == &LO_STRING_CLASS:
        return align8(offset_of(StringObject, data) + obj.length)   # 20 + length on 64-bit
    else:
        return align8(class.instance_size)
```

Use the **field offset** `offset_of(StringObject, data)` (= 20 on 64-bit), never `size_of(StringObject)` (= 24) — the offset-of-not-size-of rule from ABI §2.2. This is the single most common correctness trap in the copy loop; get it wrong and every string copy reads four bytes short of the tail or four bytes into padding.

### 2.3 Forwarding protocol

When an object is evacuated from from-space to to-space, the from-space original becomes a tombstone carrying the new address. Storage:

- The **forwarding address** overwrites the original's `class_descriptor` slot (pointer-sized; 8 bytes on 64-bit, 4 on WASM — a pointer fits on both, and the 16-byte header guarantees room).
- The **forwarding flag** is the dedicated bit in `gc_bits` (ABI §2 documents `gc_bits` as "mark, age, forwarding flag"). CC pins which bit and documents it once in `gc.rs`; the other two skeletons match.

Order matters: read the size and copy the bytes **before** clobbering `class_descriptor`, because both `size()` and the byte copy read the original descriptor. The copy carries the intact descriptor into to-space with a clear forwarding flag; only the original is mutated into a tombstone.

```
forward(p):
    if p == null:                     return null
    if p not in from-space:           return p          # immortal / non-heap: leave untouched
    if forwarding-flag(p) set:        return p.class_descriptor   # already moved; slot holds new addr
    n = size(p)
    copy n bytes  p -> free
    p.class_descriptor = free         # install tombstone
    set forwarding-flag(p)
    new = free; free += n
    return new
```

The "not in from-space" check is what keeps immortal objects (LO_EMPTY_STRING, §2.5) safe with no special case in the copy loop — they are never *in* from-space, so `forward` returns them unchanged.

### 2.4 Collection

`lo_gc_collect` performs a flip and a Cheney scan:

1. **Flip.** Swap the from/to roles. Set `scan = free = start(to-space)`.
2. **Scan roots.** Walk the shadow-stack chain from `current_frame` via `parent` to null (ABI §3.3). For each frame, for each root slot `i` in `0..num_roots`, read the slot at `frame_base + offset_of(ShadowFrame, roots) + i * ptr_size` (offset-of, not size-of — = 16 on 64-bit) and rewrite it: `*slot = forward(*slot)`. The shadow stack is the complete root set; the runtime holds no other live object pointers (LO_EMPTY_STRING is immortal, not a movable root).
3. **Cheney loop.** While `scan < free`: let `obj = scan`; for each pointer field via `class.pointer_offsets[0 .. pointer_count]`, rewrite `*(obj + off) = forward(*(obj + off))`; then `scan += size(obj)`. Strings have `pointer_count == 0`, so they only advance `scan` — but `size()` must still use the String variable-size branch to advance correctly (§2.2).
4. **Done** when `scan == free`. The old from-space is now entirely free for the next cycle. Pre-zeroing it is unnecessary: evacuated objects carry their live contents, and post-GC allocations are zeroed by `lo_alloc` per its existing contract (ABI §3.1).

### 2.5 Immortal objects

`LO_EMPTY_STRING` is a canonical zero-length `StringObject` that codegen references as a read-only static and that the runtime must never move or collect (ABI §2.3). It is defined as a **read-only static object in `.rodata`** — not heap-allocated — so its address is a link-time constant and it lies outside both semispaces by construction. This replaces the WS-1 init-time allocation: `lo_runtime_init` no longer allocates the empty string (Phase A.1). Being a zero-length string, it has no inline tail, so the whole object is a fixed compile-time constant: `{ class_descriptor = &LO_STRING_CLASS, gc_bits = 0, flags = 0, length = 0 }`. It joins the class descriptors it already sits beside in ABI §2.3, which are likewise static.

The binding invariant this rests on holds for every collector on the P3 menu, not just Cheney: **a collector never moves, reclaims, or mutates in place any object outside its collectable heap.** Cheney needs only the first two — `forward`'s "not in from-space" range-check returns the empty string untouched, with no special case, and Cheney never writes an immortal object's header. The mutate-in-place clause matters for the *other* menu collectors: mark-compact sets a mark bit in `gc_bits` in place, and a generational collector writes age/forwarding bits. Because the empty string is in read-only storage, such a collector that forgets to range-guard before writing the header **faults loudly** (a write to `.rodata` traps) rather than silently corrupting a shared object — the better failure mode in a course teaching GC, and one that points straight at the missing guard. No collector ever *needs* to write an immortal object's header (an immortal object is trivially always-live and never relocated), so read-only storage costs nothing and only removes a footgun.

**Cascade (SC follow-up, not CC's).** `.rodata` placement makes ABI §2.3 and §3.6 stale where they describe `LO_EMPTY_STRING` as allocated during `lo_runtime_init`, and it sharpens an open ABI-wording point: the `LO_EMPTY_STRING` symbol now most naturally denotes the *object* (link-time-constant address, so codegen embeds it with no load) rather than a pointer variable. SC reconciles the ABI text; recorded under Resolved design decisions so the cascade isn't lost.

### 2.6 Write barrier

No change. ABI §3.4 already ships `lo_gc_write_barrier` as a bare store, which is correct for any non-generational collector including Cheney. CC verifies it is present and bare-store, and leaves it.

---

## 3. Implementation phases

Forward-walking pre/postconditions per the runbook discipline; each phase's preconditions follow from the prior phase's postconditions.

### Phase A — Reference implementation in Rust

**Preconditions.** WS-1 merged and CI-green; `rust/` skeleton builds clean with stubbed `gc.rs`. `runtime-abi.md` present at repo root. `LO_EMPTY_STRING` placement settled — `.rodata` static (§2.5); the WS-1 init-time allocation is replaced, not extended.

**Steps.**

A.1 — Restructure the heap (`alloc.rs`) into two equal semispaces (§2.1). Replace the WS-1 init-time empty-string allocation with the `.rodata` static definition (§2.5); a true `static` holding the raw `class_descriptor` pointer needs an `unsafe impl Sync` on the struct in Rust (trivial; note it). `lo_runtime_init` no longer allocates `LO_EMPTY_STRING`.

A.2 — Implement `size()`, `forward()`, and the collection routine in `gc.rs` (§2.2–2.4). Document the chosen `gc_bits` forwarding-flag bit here.

A.3 — Wire the `lo_alloc` OOM path (§2.1 final paragraph, ABI §3.1): on no-fit, call `lo_gc_collect()`, retry the bump once, and abort via the existing OOM contract only if the retry still fails.

A.4 — GC unit tests under `rust/tests/` (or `src/tests/`): (i) collection with a known live graph preserves reachable objects and updates root + field pointers; (ii) collection reclaims an unreachable object (heap occupancy drops); (iii) a variable-size String survives a collection intact (round-trip its bytes); (iv) `LO_EMPTY_STRING` is unmoved across a collection (pointer identity stable); (v) allocation pressure past one semispace (set `LO_HEAP_SIZE` small) triggers GC and continues.

**Postconditions.** Rust skeleton builds clean (native; WASM if toolchain present), all WS-1 tests plus A.4 pass, `clippy`/`fmt` silent. `lo_gc_collect` is no longer a stub.

**Verification.** From `rust/`: `cargo test`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`.

**Notes-to-self.** `runbooks/notes/cc-ws2-phaseA-notes.md`: the forwarding-flag bit chosen; any `repr(C)`/aliasing pattern for the tombstone overwrite; the `unsafe impl Sync` form used for the `.rodata` `LO_EMPTY_STRING` static.

### Phase B — Replicate in Zig and C++

**Preconditions.** Phase A complete and merged; Rust is the reference the other two match byte-for-byte on a given target.

**Steps.** Mirror Phase A in `zig/src/gc.zig` + `zig/src/alloc.zig` and `cpp/src/gc.cpp` + `cpp/src/alloc.cpp`, same algorithm, idiomatic per language. Use the **same** forwarding-flag bit and the same heap layout so cross-skeleton behavior is identical. Replicate the A.4 tests in each language's native framework (`zig build test`; Catch2/GoogleTest for C++).

**Postconditions.** All three skeletons build clean and pass GC tests; the forwarding-flag bit and heap geometry agree across the three.

**Verification.** Zig from `zig/`: `zig build test`, `zig fmt --check src`. C++ from `cpp/`: `cmake --build build && ctest --test-dir build`, `clang-format --dry-run --Werror`.

**Notes-to-self.** `cc-ws2-phaseB-notes.md`: any layout-compat check confirming byte-identical Object headers and tombstone encoding across the three.

---

## 4. Conformance and acceptance (WS-2)

This collector is the precondition WS-2 was waiting on. Once Phases A and B merge, WS-2 itself runs:

1. For each skeleton (Rust, Zig, C++), with Cheney linked, run the shared corpus through the WS-1 cross-skeleton C harness (`tests/c_harness/run.sh`).
2. The acceptance bar is ABI §4.5: a clean checkout + Cheney + the suite passes, for each skeleton — three working baselines that agree on the ABI.

**Dependency to clear first (WS-1 delta #4).** The shared `tests/lo_programs/*.lo` fixtures currently carry best-effort, *unverified* LO-3 surface syntax (`TODO(SC)` per `runbooks/notes/for-sc-ws1-spec-deltas.md`); only the `expected/*.out` files are the stable contract. Those `.lo` bodies must be grammar-valid against `planning:lo-3-reference.md` before the harness consuming them is a meaningful conformance signal. This is SC/`lo-testing` work, not CC's, but WS-2's result is only trustworthy once it's done — surfaced here so WS-2 isn't declared green on unverified fixtures.

---

## Resolved design decisions

Settled by DC on 2026-05-30; recorded here because the project retains no transcripts and the artifact is the audit trail.

**A — `LO_EMPTY_STRING` placement: `.rodata` static.** Defined as a read-only static `StringObject`, not heap-allocated; its address is a link-time constant outside both semispaces. Rationale and the cross-collector consequences are in §2.5. Supersedes SC's earlier immortal-region proposal, which was over-built for a single fixed zero-length object (it remains the right tool only if a later LO-5 feature needs many or dynamically-created pinned objects).

**B — Heap size: inherits WS-1 (5c).** `LO_HEAP_SIZE` is read at `lo_runtime_init`, so the heap size is a runtime-overridable value (16 MiB default), not a compile-time constant; the collector inherits the existing WS-1 (5c) mechanism, with each semispace half the total (§2.1). The earlier "compile-time constant" framing was corrected 2026-05-30 once DC confirmed the override is consulted at runtime. Allocation-pressure tests set `LO_HEAP_SIZE` small to force collection deterministically.

**C — Forwarding-flag bit: CC's choice.** CC picks the `gc_bits` bit in Phase A and uses it consistently across all three skeletons (preserving the cross-skeleton byte-identical-header invariant). The bit is collector-private — no two menu collectors run on one heap — so it needs no ABI pin.

**Residual SC follow-up (not CC's; does not block this runbook).** Decision A cascades into `runtime-abi.md`: §2.3 and §3.6 describe `LO_EMPTY_STRING` as allocated during `lo_runtime_init`, which static placement makes stale, and the symbol's meaning should be pinned to the object reading (link-time-constant address, codegen embeds it with no load). SC reconciles the ABI text. `TODO(SC)`.
