//! Round-trips the print/read entry points through real stdin/stdout by running
//! the `lo_io_probe` bin in a child process. A subprocess keeps stdio capture
//! clean and avoids any cross-test fd interference.

use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn print_and_read_round_trip() {
    let exe = env!("CARGO_BIN_EXE_lo_io_probe");
    let mut child = Command::new(exe)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("spawn lo_io_probe");

    child
        .stdin
        .take()
        .expect("child stdin")
        .write_all(b"7\n")
        .expect("write stdin");

    let output = child.wait_with_output().expect("wait for child");
    assert!(
        output.status.success(),
        "probe exited non-zero: {:?}",
        output.status
    );

    // The probe echoes the int it read (7), then prints the literal 42.
    assert_eq!(String::from_utf8_lossy(&output.stdout), "7\n42\n");
}

/// Run the probe with the given stdin and return its exit code.
fn probe_exit_code(stdin: &[u8]) -> Option<i32> {
    let exe = env!("CARGO_BIN_EXE_lo_io_probe");
    let mut child = Command::new(exe)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn lo_io_probe");
    child
        .stdin
        .take()
        .expect("child stdin")
        .write_all(stdin)
        .expect("write stdin");
    child.wait().expect("wait for child").code()
}

#[test]
fn read_int_eof_exits_111() {
    // EOF before any integer characters -> exit 111 (runtime-abi.md §3.8).
    assert_eq!(probe_exit_code(b""), Some(111));
}

#[test]
fn read_int_malformed_exits_110() {
    // A non-numeric token present -> malformed, exit 110 (not EOF).
    assert_eq!(probe_exit_code(b"abc"), Some(110));
}
