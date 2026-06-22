#!/bin/bash
# Smoke test for ghcr.io/dkuav/luciole-cuda-dev.
# dev = base + ROS 2 + LLVM 21 + .NET-less devshell + finalize-mirror.
#
# Verifies:
#   - everything guaranteed by base + runtime (subset, sourced assertions)
#   - devshell tools are installed and runnable (zsh, nvim, oh-my-zsh, etc.)
#   - LLVM 21: clang / clang-format / clang-tidy / lldb symlinks
#   - pre-commit available with cached hooks
#   - finalize-mirror.sh DID flip sources to Aliyun
#
# Expected to run INSIDE the container:
#   docker run --rm <image> bash -lc '/tmp/smoke/_lib.sh; source /tmp/smoke/smoke-dev.sh'
set -uo pipefail

dev_main() {
    header "Inherited base/runtime sanity"
    assert_cmd_contains "non-root user 'luciole'" "luciole" id -un
    assert_cmd_contains "cmake runs" "cmake version" cmake --version
    assert_cmd_contains "ros2 CLI available" "ros2" \
        bash -lc "source /opt/ros/humble/setup.bash && ros2 --help"

    header "Devshell tools"
    # Core dev tools installed via apt (zsh/starship) or to /usr/local (nvim):
    # these are on PATH even in a non-interactive login shell.
    for tool in zsh nvim starship eza; do
        command -v "$tool" >/dev/null 2>&1 \
            && ok "tool present: $tool" \
            || fail "tool missing: $tool"
    done
    # fzf is git-cloned to ~/.fzf/bin/fzf by devshell.sh, which only adds it to
    # PATH via .bashrc/.zshrc (NOT .profile). A non-interactive `bash -lc` smoke
    # shell therefore won't see it on PATH — verify the binary exists directly.
    assert_path_executable "fzf installed" "$HOME/.fzf/bin/fzf"
    # nvm + node live in /home/luciole/.nvm
    assert_cmd_contains "node via nvm" "v" \
        bash -lc '. "$HOME/.nvm/nvm.sh" && node --version'
    # oh-my-zsh cloned into ~/.oh-my-zsh
    if [ -d "$HOME/.oh-my-zsh" ]; then
        ok "oh-my-zsh installed"
    else
        fail "oh-my-zsh directory missing (~/.oh-my-zsh)"
    fi
    # zoxide binary under ~/.local/bin
    if command -v zoxide >/dev/null 2>&1 || [ -x "$HOME/.local/bin/zoxide" ]; then
        ok "zoxide installed"
    else
        fail "zoxide missing"
    fi

    header "LLVM 21 toolchain"
    assert_cmd_contains "clang v21" "clang version 21" clang --version
    assert_cmd        "clang-format-21 symlink"      clang-format --version
    assert_cmd        "clang-tidy-21 symlink"        clang-tidy --version
    assert_cmd        "lldb-21 symlink"              lldb --version

    header "Pre-commit with cached hooks"
    assert_cmd_contains "pre-commit version" "pre-commit" pre-commit --version
    # precommit.sh pre-caches hook environments under ~/.cache/pre-commit during
    # image build so users can run hooks offline. We don't run a hook here
    # (the image does not ship a .pre-commit-config.yaml; that lives in
    # downstream repos). Instead we verify the cache directory is populated,
    # which proves install-hooks succeeded at build time.
    if [ -d "$HOME/.cache/pre-commit" ] && \
       [ -n "$(find "$HOME/.cache/pre-commit" -mindepth 1 -maxdepth 2 -print -quit 2>/dev/null)" ]; then
        ok "pre-commit hook cache populated (~/.cache/pre-commit)"
    else
        fail "pre-commit hook cache empty or missing (~/.cache/pre-commit)" \
             "precommit.sh may have failed during image build"
    fi

    header "finalize-mirror applied (Tier-2 policy)"
    if [ -f /etc/pip.conf ] && grep -q aliyun /etc/pip.conf 2>/dev/null; then
        ok "pip → Aliyun (/etc/pip.conf)"
    else
        fail "finalize-mirror.sh did not set /etc/pip.conf to Aliyun"
    fi

    smoke_summary
}

dev_main
