#include "lo_runtime/init.h"

#include "lo_runtime/alloc.h"
#include "lo_runtime/shadow_stack.h"

// LO_EMPTY_STRING is a `.rodata` static and needs no initialization
// (runtime-abi.md §2.3, §3.6; runbook WS-2 §2.5) — the WS-1 init-time allocation
// is gone.
extern "C" void lo_runtime_init() {
  lo::heap_init();
  lo::reset_shadow_stack();
}

extern "C" void lo_runtime_shutdown() {
  lo::reset_shadow_stack();
  lo::heap_shutdown();
}
