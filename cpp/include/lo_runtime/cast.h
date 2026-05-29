// Type operations (runtime-abi.md §3.5). Both stubbed — the team implements these
// in P3.
#pragma once

#include "lo_runtime/object.h"

extern "C" {
Object *lo_cast_check(Object *obj, const ClassDescriptor *target);
bool lo_instanceof(Object *obj, const ClassDescriptor *target);
}
