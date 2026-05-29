// Shadow-stack root tracking (runtime-abi.md §3.3).
#pragma once

#include "lo_runtime/object.h"

extern "C" {
void lo_push_frame(ShadowFrame *frame);
void lo_pop_frame();
}

namespace lo {
// Test/debug hooks (not part of the ABI).
ShadowFrame *current_frame();
void reset_shadow_stack();
} // namespace lo
