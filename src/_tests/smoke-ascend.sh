#!/bin/bash
# ARM64 Ascend development checks that do not require a host NPU or driver.
# Sourced after _lib.sh by tools.images test.
set -uo pipefail

header "Identity and vendor environment"
assert_cmd_contains "ARM64 host" "aarch64" uname -m
assert_cmd_contains "default user" "luciole" id -un
assert_cmd "passwordless sudo" sudo -n true
assert_cmd "writable workspace" test -w /work
assert_cmd "CANN headers" test -r "${ASCEND_HOME_PATH}/include/acl/acl.h"
assert_cmd "CANN operators" test -d "${ASCEND_OPP_PATH}"
assert_cmd "Bisheng compiler" command -v bisheng
assert_cmd_contains "locked SSH account" " L " sudo -n passwd --status luciole

header "Development tools"
for tool in cmake ninja git clangd gdb rg fd bat gosu landscape-sysinfo uv ty zsh nvim eza starship; do
    assert_cmd "${tool} available" bash -c "command -v ${tool}"
done
assert_cmd_contains "CMake 4.3.2" "cmake version 4.3.2" cmake --version
assert_cmd "fzf installed" test -x "${HOME}/.fzf/bin/fzf"
assert_cmd "Python package check" ascend-pip-check
assert_cmd "vendor Python and TorchNPU metadata" python3 -c '
from importlib.metadata import version
from pathlib import Path
import sys
import sysconfig
assert sys.version_info[:2] == (3, 12)
assert sys.prefix.startswith("/usr/local/python3.12.")
assert version("torch").split("+")[0] == "2.14.0"
assert version("torch-npu") == "2.14.0"
assert Path(sysconfig.get_path("include"), "Python.h").is_file()
'
assert_cmd "zsh recovers vendor environment" env -i HOME="${HOME}" PATH=/usr/bin:/bin zsh -ec 'test -r "${ASCEND_HOME_PATH}/include/acl/acl.h"; command -v bisheng; test "$(python3 -c "import sys; print(sys.version_info.minor)")" = 12'
assert_cmd "bash login recovers vendor Python" bash -lc 'test "$(python3 -c "import sys; print(sys.version_info.minor)")" = 12'

header "Entrypoint and SSH modes"
assert_cmd "shared entrypoint executable" test -x /usr/local/bin/docker-entrypoint.sh
assert_cmd "Ascend entrypoint executable" test -x /usr/local/bin/ascend-entrypoint
assert_cmd "disabled mode accepts command" env SSH_MODE=disabled /usr/local/bin/ascend-entrypoint true
assert_cmd_contains "key-only requires key" "requires a non-empty" bash -c 'SSH_MODE=key-only /usr/local/bin/ascend-entrypoint true 2>&1 || true'
assert_cmd "password mode starts sshd" env SSH_MODE=password /usr/local/bin/ascend-entrypoint true
assert_cmd "sshd running" pgrep -x sshd
sudo -n pkill -x sshd || true

smoke_summary
