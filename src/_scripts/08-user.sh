#!/bin/bash
# Create the non-root user with sudo privileges and set up XDG runtime dir.
# Reads USERNAME (default: luciole), USER_UID (default: 1000), USER_GID (default: USER_UID).
set -euo pipefail

USERNAME_VAL=${USERNAME:-luciole}
USER_UID_VAL=${USER_UID:-1000}
USER_GID_VAL=${USER_GID:-${USER_UID_VAL}}

# Remove any existing user/group occupying the target UID/GID
existing_user=$(getent passwd "${USER_UID_VAL}" | cut -d: -f1 || true)
if [ -n "${existing_user}" ]; then
    home_dir=$(getent passwd "${USER_UID_VAL}" | cut -d: -f6)
    userdel "${existing_user}"
    rm -rf "${home_dir}"
fi

existing_group=$(getent group "${USER_GID_VAL}" | cut -d: -f1 || true)
if [ -n "${existing_group}" ]; then
    groupdel "${existing_group}"
fi

groupadd --gid "${USER_GID_VAL}" "${USERNAME_VAL}"
useradd --uid "${USER_UID_VAL}" --gid "${USER_GID_VAL}" -m "${USERNAME_VAL}"

apt-get update && apt-get install -y sudo && rm -rf /var/lib/apt/lists/*
echo "${USERNAME_VAL} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/"${USERNAME_VAL}"
chmod 0440 /etc/sudoers.d/"${USERNAME_VAL}"

# XDG runtime dir — needed for VS Code IPC sockets and GUI apps
mkdir -p /run/user/"${USER_UID_VAL}"
chown "${USERNAME_VAL}":"${USERNAME_VAL}" /run/user/"${USER_UID_VAL}"
chmod 0700 /run/user/"${USER_UID_VAL}"
