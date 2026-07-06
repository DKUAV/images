#!/bin/bash
# Developer CLI toolset installed on top of a minimal system layer.
# Split out of system.sh so that:
#   - stable system bootstrap (timezone, locale, apt) lives in system.sh
#   - the frequently-edited developer tool list lives here
#   - GUI / WSLg deps live separately in wslg.sh
# Run as root (usually right after system.sh).
set -euo pipefail

# `system.sh` cleans its own apt lists, so refresh the index here.
apt-get update

# --- Editor / VCS / web / archive ---
apt-get -y install vim git curl zip unzip trash-cli git-lfs rsync tree \
    tmux screen cloc man htop ripgrep sudo

# --- Build / debug ---
apt-get -y install build-essential ninja-build gdb systemd-coredump \
    cmake parallel libssl-dev \
    libgflags-dev libgoogle-glog-dev libgtest-dev libgmock-dev

# --- SSH / OpenSSL / privilege drop ---
# openssh-server  → remote shell access (sshd launched at runtime by the entrypoint)
# gosu            → clean, signal-friendly privilege drop in the entrypoint
#                   (preferred over `su`; ships natively via apt on amd64+arm64)
apt-get -y install --no-install-recommends openssl openssh-server gosu

# --- Networking / fs ---
apt-get -y install iputils-ping nfs-common acl landscape-common

# --- Misc / CLI utilities ---
apt-get -y install fd-find bat

# fd ships as `fdfind` on Debian/Ubuntu → expose as `fd`
ln -sf "$(which fdfind)" /usr/local/bin/fd

# bat ships as `batcat` on Debian/Ubuntu → expose as `bat`
ln -sf "$(which batcat)" /usr/local/bin/bat

# --- Media (lightweight CLI utility; commonly used inside dev shells) ---
apt-get -y install ffmpeg

# --- OpenCV (for computer vision / image processing) ---
apt-get -y install libopencv-dev

rm -rf /var/lib/apt/lists/*
