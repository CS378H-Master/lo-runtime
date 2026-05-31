// Special exported statics (runtime-abi.md §2.3): the built-in class descriptors
// and the canonical empty-string singleton, referenced by codegen.
#pragma once

#include "lo_runtime/object.h"

extern "C" {
extern const ClassDescriptor LO_STRING_CLASS;
extern const ClassDescriptor LO_INT_BOX_CLASS;
extern const ClassDescriptor LO_BOOL_BOX_CLASS;
// The canonical length-0 String (runtime-abi.md §2.3, runbook WS-2 §2.5): a
// read-only `.rodata` static *object*, not heap-allocated. The symbol denotes the
// object itself; its address is a link-time constant outside the managed heap, so
// the collector never moves or reclaims it. Replaces the WS-1 init-time
// allocation.
extern const StringObject LO_EMPTY_STRING;
}
