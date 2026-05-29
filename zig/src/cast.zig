//! Type operations (`runtime-abi.md` §3.5). Both **stubbed** — the team
//! implements these in P3.
//!
//! Hints (from the ABI): `lo_cast_check` returns `obj` if its class is `target`
//! or a descendant, else aborts (exit 101); null `obj` short-circuits to null.
//! `lo_instanceof` returns a bool and never aborts; null receiver yields false.
//! Both walk `ClassDescriptor.parent` up the single-inheritance chain.

const object = @import("object.zig");
const Object = object.Object;
const ClassDescriptor = object.ClassDescriptor;

/// Checked downcast: return `obj` if its class is `target` or a descendant; abort
/// (exit 101) otherwise. Null `obj` returns null.
pub export fn lo_cast_check(obj: ?*Object, target: *const ClassDescriptor) ?*Object {
    _ = obj;
    _ = target;
    @panic("lo_cast_check: team implements per P3");
}

/// Return true iff `obj`'s class is `target` or a descendant. Null `obj` yields
/// false; never aborts.
pub export fn lo_instanceof(obj: ?*Object, target: *const ClassDescriptor) bool {
    _ = obj;
    _ = target;
    @panic("lo_instanceof: team implements per P3");
}
