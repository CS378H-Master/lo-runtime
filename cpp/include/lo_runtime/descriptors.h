// Special exported statics (runtime-abi.md §2.3): the built-in class descriptors
// and the canonical empty-string singleton, referenced by codegen.
#pragma once

#include "lo_runtime/object.h"

extern "C" {
extern const ClassDescriptor LO_STRING_CLASS;
extern const ClassDescriptor LO_INT_BOX_CLASS;
extern const ClassDescriptor LO_BOOL_BOX_CLASS;
extern Object *LO_EMPTY_STRING;
}

namespace lo {
// Allocate / clear the LO_EMPTY_STRING singleton (init / shutdown).
void init_empty_string();
void clear_empty_string();
} // namespace lo
