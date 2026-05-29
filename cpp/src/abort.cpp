#include "lo_runtime/abort.h"

#include <cstdio>
#include <cstdlib>
#include <string>

namespace lo {

void runtime_abort(const char *msg, int code) {
#ifdef __wasm__
  (void)msg;
  (void)code;
  __builtin_trap();
#else
  std::fprintf(stderr, "%s\n", msg);
  std::exit(code);
#endif
}

} // namespace lo

extern "C" void lo_abort_null_receiver(const char *method_name, std::uint32_t method_name_len) {
#ifdef __wasm__
  (void)method_name;
  (void)method_name_len;
  __builtin_trap();
#else
  std::string msg = "lo_abort_null_receiver: cannot dispatch ";
  if (method_name != nullptr) {
    msg.append(method_name, method_name_len);
  } else {
    msg.append("<unknown>");
  }
  std::fprintf(stderr, "%s\n", msg.c_str());
  std::exit(102);
#endif
}
