#!/bin/bash
# SSH server bootstrap (BUILD-TIME only).
#
# Runs during `docker build`. Everything here must be declarative / persisted
# to disk — a build layer **cannot** actually run a daemon. Starting sshd at
# runtime is the entrypoint's job (see src/_assets/docker-entrypoint.sh).
#
# What this script does:
#   - Generates host keys if missing (openssh-server's postinst normally does
#     this, but only when the service manager is available; in a build layer it
#     is skipped, so we do it explicitly).
#   - Enables public-key auth and root login for remote dev access.
#   - Prepares ~/.ssh/authorized_keys for BOTH root and the non-root user, so
#     ssh keys mounted/baked in at runtime work for either account.
#
# Reads USERNAME (default: luciole), USER_UID, USER_GID.
set -euo pipefail

USERNAME_VAL=${USERNAME:-luciole}
USER_UID_VAL=${USER_UID:-1000}

# /run/sshd is where sshd chroots its priv-separated child at runtime.
# Create it here so the entrypoint doesn't need root-only mkdir work.
mkdir -p /run/sshd
chmod 0755 /run/sshd

# Generate host keys (no-op if already present, e.g. openssh-server postinst
# ran for this layer).
ssh-keygen -A >/dev/null 2>&1 || true

# Enable public-key auth and permit root login for remote dev access.
# Use a marker so re-running the script (idempotent builds) doesn't duplicate.
if ! grep -q "^PubkeyAuthentication yes"      /etc/ssh/sshd_config; then
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
fi
if ! grep -q "^PermitRootLogin yes"           /etc/ssh/sshd_config; then
    echo "PermitRootLogin yes"      >> /etc/ssh/sshd_config
fi

# Seed authorized_keys for root.
mkdir -p /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0700 /root/.ssh
chmod 0600 /root/.ssh/authorized_keys

# Seed authorized_keys for the non-root user (if the account already exists —
# in the base image ssh.sh runs before user.sh, so the user may not exist yet;
# in that case user.sh is responsible for the directory).
if id "${USERNAME_VAL}" >/dev/null 2>&1; then
    USER_HOME=$(getent passwd "${USERNAME_VAL}" | cut -d: -f6)
    if [ -n "${USER_HOME}" ]; then
        mkdir -p "${USER_HOME}/.ssh"
        touch "${USER_HOME}/.ssh/authorized_keys"
        chmod 0700 "${USER_HOME}/.ssh"
        chmod 0600 "${USER_HOME}/.ssh/authorized_keys"
        chown -R "${USERNAME_VAL}":"$(id -gn "${USERNAME_VAL}")" "${USER_HOME}/.ssh"
    fi
fi

# NOTE: do NOT call `service ssh start` / `systemctl start ssh` here — a build
# layer has no init and the daemon would die the moment the layer commits.
# Starting sshd is the entrypoint's job at container runtime.
