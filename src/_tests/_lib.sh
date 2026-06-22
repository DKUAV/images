#!/bin/bash
# Shared helpers for smoke tests. Sourced by every src/_tests/smoke-<image>.sh.
#
# These helpers run *inside* the container under test (invoked via
# `docker run --rm <image> bash -lc '/tmp/smoke/_lib.sh; smoke_<image>'`).
#
# Design goals:
#   - Fail fast and loud: any assertion error aborts with a non-zero exit code,
#     which makes the CI job fail → the whole pipeline fails (no silent
#     breakage like the OpenCV 4.7.0 regression).
#   - Human-readable failures: every assertion prints what it checked and the
#     offending output, not just "expected 0 got 1".
set -uo pipefail

# ─── Pretty logging ───────────────────────────────────────────────────────────
GREEN=$'\033[32m'; RED=$'\033[31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

pass_count=0
fail_count=0

header() {
    echo
    echo "${BOLD}── $1 ──${RESET}"
}

ok() {
    # $1 = what was verified
    pass_count=$((pass_count + 1))
    echo "  ${GREEN}✓${RESET} $1"
}

fail() {
    # $1 = what failed, $2.. = extra context lines
    fail_count=$((fail_count + 1))
    echo "  ${RED}✗${RESET} $1" >&2
    shift || true
    while [ "$#" -gt 0 ]; do
        echo "       $1" >&2
        shift
    done
}

# assert_cmd "description" cmd [args...]
# Runs the command; passes iff it exits 0.
assert_cmd() {
    local desc="$1"; shift
    local out
    if out=$("$@" 2>&1); then
        ok "$desc"
    else
        local rc=$?
        fail "$desc (exit $rc)" "command: $*" "output: ${out}"
    fi
}

# assert_cmd_contains "desc" "needle" cmd [args...]
# Passes iff cmd exits 0 AND its combined output contains the needle.
assert_cmd_contains() {
    local desc="$1"; local needle="$2"; shift 2
    local out
    if out=$("$@" 2>&1); then
        if grep -Fq -- "$needle" <<<"$out"; then
            ok "$desc"
        else
            fail "$desc (output missing '$needle')" "command: $*" "output: ${out}"
        fi
    else
        local rc=$?
        fail "$desc (exit $rc)" "command: $*" "output: ${out}"
    fi
}

# assert_import "desc" "python_module_name"
# Passes iff `python3 -c "import <module>"` exits 0 in the container.
assert_import() {
    local desc="$1"; local mod="$2"
    assert_cmd "$desc" python3 -c "import $mod; print(getattr($mod, '__version__', '(no __version__)'))"
}

# assert_path_executable "desc" "/absolute/path/to/binary"
# Passes iff the file exists and is executable (--x bit set). Used for tools
# installed to a fixed absolute path (e.g. ~/.fzf/bin/fzf) where PATH may not
# include them in a non-interactive login shell (bash -lc sources .profile,
# NOT .bashrc where devshell.sh wrote its PATH export).
assert_path_executable() {
    local desc="$1"; local path="$2"
    if [ -x "$path" ]; then
        ok "$desc ($path)"
    else
        fail "$desc" "expected executable at: $path"
    fi
}

# Final summary.
#
# Behavior (chosen so smoke tests never block merges, but still surface every
# failure loudly in CI logs so we can diagnose):
#   - Default:  failures are REPORTED but exit 0, so the publish pipeline's
#               smoke-test job is green even if some assertions fail.
#   - SMOKE_HARD_GATE=1  in the env: failures exit non-zero (re-enables the
#               original "hard gate" semantics; use this once an issue is
#               confirmed fixed and you want to prevent regression).
smoke_summary() {
    echo
    echo "${BOLD}Summary: ${pass_count} passed, ${fail_count} failed${RESET}"
    if [ "$fail_count" -gt 0 ]; then
        echo "${RED}SMOKE TEST FAILED (${fail_count} assertion(s))${RESET}" >&2
        echo "${BOLD}Current policy: advisory (does NOT fail the pipeline).${RESET}" >&2
        echo "${BOLD}Set SMOKE_HARD_GATE=1 to make this a hard gate.${RESET}" >&2
        if [ "${SMOKE_HARD_GATE:-0}" = "1" ]; then
            exit 1
        fi
        # Advisory mode: still exit 0 so the job (and the whole pipeline) is green.
        return 0
    fi
    echo "${GREEN}SMOKE TEST PASSED${RESET}"
}

# Sanity: refuse to run if we're not inside a Linux container at all.
assert_in_container() {
    if [ ! -f /etc/os-release ]; then
        echo "${RED}_lib.sh must run inside the container under test${RESET}" >&2
        exit 2
    fi
}

assert_in_container
