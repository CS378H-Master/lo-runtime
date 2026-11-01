# Contributed GC stress tests (P3)

Five LO programs in the course's stress-test format, each aimed at a different
collector invariant. Each one targets a bug that none of the course's public
stress tests (`lo-testing/p3-gc-stress-tests/`) is written to catch. For each,
we planted that bug in a copy of our runtime and checked that the test fails.

| Test | Invariant | Planted bug it catches |
|---|---|---|
| `gc_01_unmoved_anchor_fixup` | Reference fixup rewrites the fields of *every* live object, including ones that do not move | Fixup skips objects whose address is unchanged |
| `gc_02_overlapping_slide` | An object that slides down by less than its own size is copied overlap-safely | Copying high-to-low, or copying the tail block first |
| `gc_03_survivors_then_die` | Objects that survived one collection are reclaimed once they die | Mark bits left set after collection, so old survivors are kept forever |
| `gc_04_deep_list_marking` | Marking uses an explicit worklist, not one stack frame per pointer followed | Recursive marking (overflows the stack on a 170,000-link chain) |
| `gc_05_every_pointer_field` | Scanning visits every pointer offset the class descriptor lists, and nothing else | Scanning only the first field, skipping the last, or assuming pointer fields are contiguous |

## Format

Each `LO-3/ValidPrograms/<stem>.lo` carries the stress-test header:

```
// good test case
// <what it stresses>
// main method return value: 0
// gc stress heap: <bytes>
```

and `<stem>.expected.out` holds the exact stdout. As in the public set, each
heap is between 64 KiB and 16 MiB, the peak live data is at most a quarter of
it (so a semispace collector also passes), and each program allocates over
64 MiB in total, so it collects at the default heap too. Every test passes on
our Lisp-2 collector and on the reference Cheney collector (`reference-cheney`
feature).

## Running them

From the repository root, in the course container, after `lo-build`:

```sh
source p3-grading-contract.sh && lo-build
bash tests/gc-stress/run.sh          # both targets
bash tests/gc-stress/run.sh wasm     # WASM at the default heap
bash tests/gc-stress/run.sh native   # native at the default heap and at the test's heap
```

Each test runs in the grader's three configurations: WASM at the default heap
(a WASM module has no environment, so `LO_HEAP_SIZE` cannot reach it), native
at the default heap, and native with `LO_HEAP_SIZE` set to the header's value.
To run one test by hand:

```sh
P=tests/gc-stress/LO-3/ValidPrograms/gc_01_unmoved_anchor_fixup
lo-compile "$P.lo" /tmp/t.wasm && lo-wasmrun /tmp/t.wasm | cmp - "$P.expected.out"
lo-emit-asm "$P.lo" /tmp/t.s && as --64 -o /tmp/t.o /tmp/t.s &&
    cc -no-pie -o /tmp/t /tmp/t.o "$LO_RUNTIME_NATIVE_LIB" -lpthread -ldl -lm
/tmp/t | cmp - "$P.expected.out"
LO_HEAP_SIZE=$(sed -n 's|^// gc stress heap: ||p' "$P.lo") /tmp/t | cmp - "$P.expected.out"
```
