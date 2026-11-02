#!/bin/bash
# Smoke test for ghcr.io/dkuav/luciole-cuda-base.
# Verifies the contract a Tier 2 image depends on:
#   - non-root user exists, passwordless sudo
#   - system tools + CMake binary
#   - Python entrypoint, PyTorch importable
#   - pip packages installed by cuda-pip-packages.sh import cleanly
#   - OpenCV dual setup:
#       * C++ find_package(OpenCV) resolves to an apt-owned config and links cleanly
#       * Python cv2 importable (pip wheel)
#   - Aliyun mirror is NOT applied in base (it's a Tier-2-final concern)
#
# Expected to run INSIDE the container:
#   docker run --rm <image> bash -lc '/tmp/smoke/_lib.sh; source /tmp/smoke/smoke-base.sh'
set -uo pipefail

base_main() {
    header "User & privileges"
    # NOTE: luciole-cuda-base intentionally has NO trailing `USER` directive —
    # its default user is root (inherited from the NVIDIA base) because base
    # is a build-stone for Tier 2, not a runtime container for end users. The
    # Tier 2 finals (dev / runtime) switch to `USER luciole` at their own end.
    # So we assert that the luciole *account* exists with the right uid, not
    # that we're currently running as it.
    assert_cmd_contains "user 'luciole' exists" "luciole" id luciole
    assert_cmd_contains "luciole uid is 1000" "uid=1000" id luciole
    # sudoers entry must grant passwordless sudo to luciole.
    assert_cmd "passwordless sudo granted to luciole" \
        sudo -u luciole -n true

    header "System tools"
    # NOTE: the Debian apt package name ≠ binary name in two cases we symlink:
    #   - apt `ripgrep`  → binary `rg`
    #   - apt `fd-find`  → binary `fd`   (symlinked by dev-tools.sh)
    #   - apt `bat`      → binary `bat`  (symlinked by dev-tools.sh)
    for tool in git curl wget vim tmux htop rsync rg ffmpeg gosu landscape-sysinfo; do
        command -v "$tool" >/dev/null 2>&1 \
            && ok "tool present: $tool" \
            || fail "tool missing: $tool"
    done
    # fd/bat ship as fdfind/batcat symlinked into /usr/local/bin
    assert_cmd "fd symlink present"  fd --version
    assert_cmd "bat symlink present" bat --version

    header "Default editor"
    assert_cmd_contains "EDITOR defaults to vim" "vim" printenv EDITOR
    assert_cmd_contains "VISUAL defaults to vim" "vim" printenv VISUAL
    assert_cmd_contains "editor alternative is vim" "vim" readlink -f /usr/bin/editor

    header "CMake binary (installed in base)"
    assert_cmd_contains "cmake runs" "cmake version" cmake --version

    header "Python & PyTorch"
    assert_cmd "python3 entrypoint" python3 --version
    assert_cmd "uv CLI" uv --version
    assert_cmd "ty CLI" ty --version
    assert_import "numpy importable"  numpy
    assert_import "pandas importable" pandas
    assert_import "torch importable"  torch

    header "OpenCV — Python (pip opencv-contrib-python wheel)"
    assert_import "cv2 importable" cv2

    header "OpenCV — C++ apt configuration, compilation and runtime"
    # Apt versions differ across Ubuntu releases. Verify package ownership and
    # matching CMake/header/runtime versions instead of a historical version.
    local probe_dir
    probe_dir=$(mktemp -d)
    cat > "$probe_dir/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(opencv_probe LANGUAGES CXX)
find_package(OpenCV REQUIRED)
message(STATUS "OPENCV_VERSION=${OpenCV_VERSION}")
message(STATUS "OPENCV_CONFIG=${OpenCV_CONFIG}")
add_executable(opencv_probe main.cpp)
target_include_directories(opencv_probe PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(opencv_probe PRIVATE ${OpenCV_LIBS})
EOF
    cat > "$probe_dir/main.cpp" <<'EOF'
#include <iostream>
#include <string>
#include <opencv2/core.hpp>

/** Report the runtime version and require matching installed headers. */
int main() {
    const std::string runtimeVersion = cv::getVersionString();
    std::cout << runtimeVersion << '\n';
    return runtimeVersion == CV_VERSION ? 0 : 1;
}
EOF
    if cmake -S "$probe_dir" -B "$probe_dir/build" >"$probe_dir/configure.log" 2>&1; then
        local ver config owner runtime_ver
        ver=$(sed -n 's/^-- OPENCV_VERSION=//p' "$probe_dir/configure.log")
        config=$(sed -n 's/^-- OPENCV_CONFIG=//p' "$probe_dir/configure.log")
        owner=$(dpkg-query -S "$config" 2>/dev/null || true)
        if [ -z "$ver" ]; then
            fail "find_package(OpenCV) succeeded but version not reported"
        elif [[ "$owner" != libopencv-dev:* ]]; then
            fail "find_package(OpenCV) → ${ver}, config is not owned by apt libopencv-dev" \
                 "resolved config: ${config}"
        elif ! cmake --build "$probe_dir/build" >"$probe_dir/build.log" 2>&1; then
            fail "OpenCV ${ver} C++ compile/link failed"
            sed 's/^/       /' "$probe_dir/build.log" >&2 || true
        elif runtime_ver=$("$probe_dir/build/opencv_probe" 2>"$probe_dir/runtime.log") \
             && [ "$runtime_ver" = "$ver" ]; then
            ok "find_package(OpenCV) → ${ver} (apt config, headers and runtime agree)"
        else
            fail "OpenCV ${ver} runtime failed or version mismatch: ${runtime_ver}"
            sed 's/^/       /' "$probe_dir/runtime.log" >&2 || true
        fi
    else
        fail "find_package(OpenCV) FAILED"
        sed 's/^/       /' "$probe_dir/configure.log" >&2 || true
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
