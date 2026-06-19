#!/bin/bash
# Smoke test for ghcr.io/dkuav/luciole-cuda-base.
# Verifies the contract a Tier 2 image depends on:
#   - non-root user exists, passwordless sudo
#   - system tools + CMake binary
#   - Python entrypoint, PyTorch importable
#   - pip packages installed by pip-packages.sh import cleanly
#   - OpenCV dual setup:
#       * C++ find_package(OpenCV) resolves to apt 4.5.4 (NOT NVIDIA's 4.7.0)
#       * Python cv2 importable (pip wheel)
#   - Aliyun mirror is NOT applied in base (it's a Tier-2-final concern)
#
# Expected to run INSIDE the container:
#   docker run --rm <image> bash -lc '/tmp/smoke/_lib.sh; source /tmp/smoke/smoke-base.sh'
set -uo pipefail

base_main() {
    header "User & privileges"
    assert_cmd_contains "non-root user 'luciole' active" "luciole" id -un
    assert_cmd_contains "uid is 1000" "uid=1000" id -u
    assert_cmd "passwordless sudo works" sudo -n true

    header "System tools"
    for tool in git curl wget vim tmux htop rsync ripgrep ffmpeg; do
        command -v "$tool" >/dev/null 2>&1 \
            && ok "tool present: $tool" \
            || fail "tool missing: $tool"
    done
    # fd/bat ship as fdfind/batcat symlinked into /usr/local/bin
    assert_cmd "fd symlink present"  fd --version
    assert_cmd "bat symlink present" bat --version

    header "CMake binary (installed in base)"
    assert_cmd_contains "cmake runs" "cmake version" cmake --version

    header "Python & PyTorch"
    assert_cmd "python3 entrypoint" python3 --version
    assert_import "numpy importable"  numpy
    assert_import "pandas importable" pandas
    assert_import "torch importable"  torch

    header "OpenCV — Python (pip opencv-contrib-python wheel)"
    assert_import "cv2 importable" cv2

    header "OpenCV — C++ find_package(OpenCV) resolves to apt 4.5.4, not NVIDIA 4.7.0"
    # Minimal CMake probe in a temp project: require OpenCV and print its version.
    # This is exactly the failure mode the opencv.sh quarantine defends against.
    local probe_dir
    probe_dir=$(mktemp -d)
    cat > "$probe_dir/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(opencv_probe LANGUAGES CXX)
find_package(OpenCV REQUIRED)
message(STATUS "OPENCV_VERSION=${OpenCV_VERSION}")
EOF
    if (cd "$probe_dir" && cmake -S . -B build >/tmp/cmake_probe.log 2>&1); then
        local ver
        ver=$(grep -oP 'OPENCV_VERSION=\K[0-9.]+' /tmp/cmake_probe.log || true)
        if [ -n "$ver" ] && [[ "$ver" == 4.5.* ]]; then
            ok "find_package(OpenCV) → ${ver} (apt 4.5.x, correct)"
        elif [ -n "$ver" ]; then
            fail "find_package(OpenCV) → ${ver}, expected 4.5.x (NVIDIA 4.7.0 leak?)" \
                 "see opencv.sh / docs/opencv-status.md"
        else
            fail "find_package(OpenCV) succeeded but version not reported"
            sed 's/^/       /' /tmp/cmake_probe.log >&2 || true
        fi
    else
        fail "find_package(OpenCV) FAILED"
        sed 's/^/       /' /tmp/cmake_probe.log >&2 || true
    fi
    rm -rf "$probe_dir"

    header "Mirror policy — base keeps default sources"
    # finalize-mirror.sh runs ONLY in Tier 2 finals; base must ship upstream sources
    # so its own Tier 2 children don't inherit a China-only mirror at build time.
    if [ -f /etc/pip.conf ] && grep -q aliyun /etc/pip.conf 2>/dev/null; then
        fail "base must NOT switch pip to Aliyun (that's a Tier-2-final step)"
    else
        ok "pip not yet pointed at Aliyun (correct for base)"
    fi

    smoke_summary
}

base_main
