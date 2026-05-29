//! Runtime aborts (`runtime-abi.md` §3.8). Native: message to stderr + exit with
//! the ABI status code. WASM: `unreachable` trap, which the host harness reports
//! (distinguishing kinds by the accompanying message).
//!
//! Each abort has a native and a WASM implementation selected at comptime, so the
//! untaken one is never analyzed (the native bodies reference `std.process`/
//! stderr, which freestanding WASM lacks).

const std = @import("std");
const builtin = @import("builtin");

const is_wasm = builtin.cpu.arch.isWasm();

/// Abort with `msg` on stderr and `code` as the exit status (native), or a trap
/// (WASM). Never returns.
pub const runtimeAbort = if (is_wasm) abortWasm else abortNative;

fn abortNative(msg: []const u8, code: u8) noreturn {
    std.debug.print("{s}\n", .{msg});
    std.process.exit(code);
}

fn abortWasm(msg: []const u8, code: u8) noreturn {
    _ = msg;
    _ = code;
    unreachable;
}

/// Abort on a null receiver at method dispatch (`runtime-abi.md` §3.8). Codegen
/// emits a null check before each dispatch and calls this on failure. Exit 102
/// (native) / trap (WASM).
pub export fn lo_abort_null_receiver(method_name: ?[*]const u8, method_name_len: u32) noreturn {
    nullReceiver(method_name, method_name_len);
}

const nullReceiver = if (is_wasm) nullReceiverWasm else nullReceiverNative;

fn nullReceiverNative(method_name: ?[*]const u8, method_name_len: u32) noreturn {
    var buf: [256]u8 = undefined;
    const name: []const u8 = if (method_name) |p| p[0..method_name_len] else "<unknown>";
    const msg = std.fmt.bufPrint(
        &buf,
        "lo_abort_null_receiver: cannot dispatch {s}",
        .{name},
    ) catch "lo_abort_null_receiver: cannot dispatch";
    runtimeAbort(msg, 102);
}

fn nullReceiverWasm(method_name: ?[*]const u8, method_name_len: u32) noreturn {
    _ = method_name;
    _ = method_name_len;
    unreachable;
}
