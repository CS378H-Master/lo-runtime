#!/usr/bin/env bash
#
# install-hooks.sh — install the lo-runtime pre-commit hook.
#
# The hook runs every available language's formatter and linter plus a couple of
# universal checks (trailing whitespace, secrets scan). Each check is guarded by
# a `command -v` probe so a contributor working on only one skeleton is not
# blocked by a toolchain they don't have installed.
#
# Run once after cloning:
#
#     bash scripts/install-hooks.sh
#
set -euo pipefail

repo_root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
hook_dir="$repo_root/.git/hooks"
hook_path="$hook_dir/pre-commit"

mkdir -p "$hook_dir"

cat > "$hook_path" <<'HOOK'
#!/usr/bin/env bash
#
# lo-runtime pre-commit hook (installed by scripts/install-hooks.sh).
# Skips any language whose toolchain is not on PATH.
#
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

status=0
fail() { echo "pre-commit: $1" >&2; status=1; }

# --- Rust -------------------------------------------------------------------
if command -v cargo >/dev/null 2>&1 && [ -f rust/Cargo.toml ]; then
  ( cd rust && cargo fmt --check ) || fail "cargo fmt --check failed (run: cd rust && cargo fmt)"
  ( cd rust && cargo clippy --all-targets -- -D warnings ) || fail "cargo clippy reported warnings"
fi

# --- Zig --------------------------------------------------------------------
if command -v zig >/dev/null 2>&1 && [ -d zig/src ]; then
  ( cd zig && zig fmt --check src ) || fail "zig fmt --check failed (run: cd zig && zig fmt src)"
fi

# --- C++ --------------------------------------------------------------------
if command -v clang-format >/dev/null 2>&1; then
  cpp_files="$(find cpp/src cpp/include \( -name '*.cpp' -o -name '*.h' \) 2>/dev/null || true)"
  if [ -n "$cpp_files" ]; then
    echo "$cpp_files" | xargs clang-format --dry-run --Werror || fail "clang-format found unformatted C++"
  fi
fi

# --- Universal: trailing whitespace ----------------------------------------
ws_hits="$(git diff --cached --check 2>/dev/null || true)"
if [ -n "$ws_hits" ]; then
  echo "$ws_hits" >&2
  fail "staged changes contain trailing whitespace / whitespace errors"
fi

# --- Universal: secrets scan ------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks protect --staged --no-banner || fail "gitleaks detected a potential secret"
fi

exit $status
HOOK

chmod +x "$hook_path"
echo "Installed pre-commit hook at $hook_path"
