// Runtime aborts (runtime-abi.md §3.8).
#pragma once

#include <cstdint>

namespace lo {
// Native: message to stderr + exit(code). WASM: __builtin_trap. Never returns.
[[noreturn]] void runtime_abort(const char *msg, int code);
} // namespace lo

extern "C" {
// Abort on a null receiver at method dispatch (exit 102 native / trap WASM).
[[noreturn]] void lo_abort_null_receiver(const char *method_name, std::uint32_t method_name_len);
}
