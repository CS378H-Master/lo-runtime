// I/O surface (runtime-abi.md §3.7).
#pragma once

#include "lo_runtime/object.h"

extern "C" {
void lo_print_int(std::int32_t n);
void lo_print_bool(bool b);
void lo_print_string(Object *s);
void lo_println();

std::int32_t lo_read_int();
bool lo_read_bool();
Object *lo_read_string();
bool lo_eof();
}
