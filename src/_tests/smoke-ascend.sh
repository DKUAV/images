#!/bin/bash
# ARM64 Ascend development checks that do not require a host NPU or driver.
# Sourced after _lib.sh by tools.images test.
set -uo pipefail

# The Bash test override avoids starting key-only SSH without a mounted public key.
# Source the installed login environment; test the real vendor wrapper below.
# shellcheck disable=SC1091
source /etc/profile.d/ascend-dev.sh

header "Identity and vendor environment"
assert_cmd_contains "ARM64 host" "aarch64" uname -m
assert_cmd "default user" test "$(id -un)" = root
assert_cmd "root UID" test "$(id -u)" -eq 0
assert_cmd "root home" test "${HOME}" = /root
assert_cmd "default SSH mode" test "${SSH_MODE}" = key-only
assert_cmd "writable workspace" test -w /work
assert_cmd "CANN headers" test -r "${ASCEND_HOME_PATH}/include/acl/acl.h"
assert_cmd "CANN operators" test -d "${ASCEND_OPP_PATH}"
assert_cmd "Bisheng compiler" command -v bisheng
assert_cmd_contains "SSH login account" "AllowUsers root" grep '^AllowUsers ' /etc/ssh/sshd_config.d/99-dev-image.conf

header "Development tools"
for tool in cmake ninja git clangd gdb rg fd bat gosu landscape-sysinfo uv ty zsh nvim eza starship; do
    assert_cmd "${tool} available" bash -c "command -v ${tool}"
done
assert_cmd_contains "CMake 4.3.2" "cmake version 4.3.2" cmake --version
assert_cmd "fzf installed" test -x "${HOME}/.fzf/bin/fzf"
assert_cmd "Python package check" ascend-pip-check
assert_cmd "Python build tools import" python3 -c 'import build, packaging, wheel, hatchling.build, hatch_vcs, editables, setuptools_scm, uv_build'
assert_cmd "uv-build executable" command -v uv-build
assert_cmd "vendor Python and TorchNPU metadata" python3 -c '
from importlib.metadata import version
from pathlib import Path
import sys
import sysconfig
assert sys.version_info[:2] == (3, 12)
assert sys.prefix.startswith("/usr/local/python3.12.")
assert version("torch").split("+")[0] == "2.10.0"
assert version("torch-npu") == "2.10.0.post7"
assert Path(sysconfig.get_path("include"), "Python.h").is_file()
'
assert_cmd "zsh recovers vendor environment" env -i HOME="${HOME}" PATH=/usr/bin:/bin zsh -ec 'test -r "${ASCEND_HOME_PATH}/include/acl/acl.h"; command -v bisheng; test "$(python3 -c "import sys; print(sys.version_info.minor)")" = 12'
assert_cmd "bash login recovers vendor Python" bash -lc 'test "$(python3 -c "import sys; print(sys.version_info.minor)")" = 12'

header "Entrypoint and SSH modes"
assert_cmd "shared entrypoint executable" test -x /usr/local/bin/docker-entrypoint
assert_cmd "Ascend entrypoint executable" test -x /usr/local/bin/ascend-entrypoint
assert_cmd "disabled mode accepts command" env SSH_MODE=disabled /usr/local/bin/ascend-entrypoint true
assert_cmd_contains "key-only requires key" "requires a non-empty" bash -c 'SSH_MODE=key-only /usr/local/bin/ascend-entrypoint true 2>&1 || true'
key_directory=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -f "${key_directory}/id_ed25519"
cat "${key_directory}/id_ed25519.pub" >/root/.ssh/authorized_keys
assert_cmd "default key-only mode starts sshd with key" /usr/local/bin/ascend-entrypoint true
assert_cmd "key-only sshd running" pgrep -x sshd
assert_cmd_contains "password authentication disabled" "PasswordAuthentication no" grep '^PasswordAuthentication ' /etc/ssh/sshd_config.d/99-dev-image.conf
pkill -x sshd || true
: >/root/.ssh/authorized_keys
rm -rf "${key_directory}"
assert_cmd_contains "root password requires secret" "requires SSH_PASSWORD_FILE" bash -c 'SSH_MODE=password /usr/local/bin/ascend-entrypoint true 2>&1 || true'
password_file=$(mktemp)
chmod 600 "${password_file}"
openssl rand -hex 32 >"${password_file}"
assert_cmd "password mode starts sshd with secret" env SSH_MODE=password SSH_PASSWORD_FILE="${password_file}" /usr/local/bin/ascend-entrypoint true
assert_cmd "sshd running" pgrep -x sshd
pkill -x sshd || true
rm -f "${password_file}"

smoke_summary
