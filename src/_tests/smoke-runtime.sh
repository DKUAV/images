#!/bin/bash
# Smoke test for ghcr.io/dkuav/luciole-cuda-runtime.
# runtime = base + ROS 2 humble/ros-base + finalize-mirror.
#
# Verifies:
#   - everything base guarantees (sourced assertions)
#   - ROS 2 binaries present, `ros2 --version` and `colcon` runnable
#   - finalize-mirror.sh DID flip sources to Aliyun (Tier-2 policy)
#   - non-root user, default shell is bash (no devshell)
#
# Expected to run INSIDE the container:
#   docker run --rm <image> bash -lc '/tmp/smoke/_lib.sh; source /tmp/smoke/smoke-runtime.sh'
set -uo pipefail

runtime_main() {
    header "Inherited from base (sanity)"
    assert_cmd "python3 entrypoint" python3 --version
    assert_cmd_contains "cmake runs" "cmake version" cmake --version
    assert_cmd_contains "non-root user 'luciole'" "luciole" id -un

    header "ROS 2 Humble (ros-base)"
    # /opt/ros/<distro>/setup.bash must exist before ROS binaries are on PATH.
    if [ -f /opt/ros/humble/setup.bash ]; then
        ok "/opt/ros/humble installed"
    else
        fail "/opt/ros/humble/setup.bash missing"
    fi
    # `ros2` is only on PATH after sourcing the setup, to avoid polluting the base shell.
    assert_cmd_contains "ros2 CLI version" "ros2" \
        bash -lc "source /opt/ros/humble/setup.bash && ros2 --help"
    assert_cmd "colcon present" \
        bash -lc "source /opt/ros/humble/setup.bash && command -v colcon"

    header "finalize-mirror applied (Tier-2 policy)"
    if [ -f /etc/pip.conf ] && grep -q aliyun /etc/pip.conf 2>/dev/null; then
        ok "pip → Aliyun (/etc/pip.conf)"
    else
        fail "finalize-mirror.sh did not set /etc/pip.conf to Aliyun"
    fi
    # apt: either deb822 ubuntu.sources or classic sources.list points to aliyun.
    if grep -rq mirrors.aliyun.com /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        ok "apt sources → Aliyun"
    else
        fail "apt sources do NOT reference Aliyun"
    fi

    header "No devshell in runtime"
    if command -v zsh >/dev/null 2>&1; then
        fail "zsh present — runtime should NOT include the devshell layer"
    else
        ok "zsh absent (correct: runtime has no devshell)"
    fi
    if command -v nvim >/dev/null 2>&1; then
        fail "nvim present — runtime should NOT include the devshell layer"
    else
        ok "nvim absent (correct: runtime has no devshell)"
    fi

    smoke_summary
}

runtime_main
