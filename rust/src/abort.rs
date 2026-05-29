//! Runtime aborts.
//!
//! Native: write the message to stderr and exit with the ABI-specified status
//! code (`runtime-abi.md` §3.8 table). WASM: execute an `unreachable` trap, which
//! the host test harness reports as an abort, distinguishing kinds by the
//! accompanying message.

/// Abort the process with `msg` on stderr and `code` as the exit status (native),
/// or an `unreachable` trap (WASM). Never returns.
pub(crate) fn runtime_abort(msg: &str, code: i32) -> ! {
    #[cfg(not(target_arch = "wasm32"))]
    {
        eprintln!("{msg}");
        std::process::exit(code);
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (msg, code);
        core::arch::wasm32::unreachable()
    }
}

/// Abort on a null receiver at method dispatch (`runtime-abi.md` §3.8). Codegen
/// emits a null check before each dispatch and calls this on failure with a
/// pointer to the method's name. Exit status 102 on native; `unreachable` on
/// WASM.
///
/// # Safety
/// `method_name`, if non-null, must point at `method_name_len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn lo_abort_null_receiver(method_name: *const u8, method_name_len: u32) -> ! {
    let name = if method_name.is_null() {
        "<unknown>"
    } else {
        let bytes = core::slice::from_raw_parts(method_name, method_name_len as usize);
        core::str::from_utf8(bytes).unwrap_or("<invalid-utf8>")
    };
    runtime_abort(
        &format!("lo_abort_null_receiver: cannot dispatch {name}"),
        102,
    )
}
