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
assert_cmd "micromamba CLI" micromamba --version
assert_cmd "Sheldon CLI" "${HOME}/.local/bin/sheldon" --version
assert_cmd "zoxide CLI" "${HOME}/.local/bin/zoxide" --version
assert_cmd "Witr CLI" witr --version
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

amct_onnx_smoke() (
    work=$(mktemp -d) || exit 1
    trap 'rm -rf -- "$work"' EXIT
    cd "$work" && mkdir calibration || exit 1

    /opt/amct/bin/python -E - <<'PY' || exit 1
import amct_onnx
import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

assert amct_onnx.AMCT_SO is not None, "AMCT custom operators could not be loaded"
shape = [1, 16, 8, 8]
rng = np.random.default_rng(42)
weights = rng.normal(0, 0.2, (16, 16, 3, 3)).astype(np.float32)
graph = helper.make_graph(
    [helper.make_node("Conv", ["x", "weights"], ["y"], name="conv", pads=[1] * 4)],
    "smoke",
    [helper.make_tensor_value_info("x", TensorProto.FLOAT, shape)],
    [helper.make_tensor_value_info("y", TensorProto.FLOAT, shape)],
    [numpy_helper.from_array(weights, "weights")],
)
model = helper.make_model(graph, ir_version=9, opset_imports=[helper.make_opsetid("", 13)])
onnx.checker.check_model(model)
onnx.save(model, "model.onnx")
rng.normal(size=shape).astype("<f4").tofile("calibration/000.bin")
PY

    amct_onnx calibration --model model.onnx --save_path int8 \
        --input_shape 'x:1,16,8,8' --data_dir calibration --data_types float32 \
        --batch_num 1 || exit 1
    test -s int8_fake_quant_model.onnx || exit 1
    /opt/amct/bin/python -E -c 'import onnx; assert any(
        node.op_type == "AscendQuant"
        for node in onnx.load("int8_deploy_model.onnx").graph.node
    ), "AMCT deploy graph has no AscendQuant node"' || exit 1
    atc --model=int8_deploy_model.onnx --framework=5 --output=int8 \
        --soc_version=Ascend910B2 --input_shape='x:1,16,8,8' && test -s int8.om
)

header "AMCT ACL and ONNX calibration"
assert_cmd "AMCT ACL library is installed in the Toolkit" \
    test -s "${ASCEND_HOME_PATH}/lib64/libamctacl.so"
assert_cmd "Calibrate ONNX on CPU and compile Ascend910B2 INT8 OM" amct_onnx_smoke

header "ONNX tools and MindStudio Probe"
assert_cmd "ONNX environment dependencies are consistent" uv pip check --python /opt/onnx/bin/python
# shellcheck source=src/_tests/onnx-tools.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/onnx-tools.sh" || exit 1

header "OM inference and benchmarking"
assert_cmd "AIS Bench CLI loads the ACL runtime" python3 -m ais_bench --help

smoke_summary
