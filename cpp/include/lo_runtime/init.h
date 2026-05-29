// Runtime lifecycle (runtime-abi.md §3.6).
#pragma once

extern "C" {
void lo_runtime_init();
void lo_runtime_shutdown();
}
