#!/bin/bash
# Container entrypoint shared by every Tier 2 final image (and inherited from
# the Tier 1 base). Responsibilities, in order:
#
#   1. Bootstrap the SSH daemon (build-time `ssh.sh` only writes config/keys;
#      a docker build layer can't actually run a long-lived service).
#   2. Drop to the non-root application user (APP_USER) via `gosu` and `exec`
#      the user-supplied command — so a plain `docker run -it <image>` lands in
#      a non-root shell, while `docker run <image> bash -lc '...'` still runs
#      as that user.
#
# APP_USER semantics:
#   - empty / unset / "root"  → keep the root identity (the Tier 1 base's
#     default, matching its "build-stone, not end-user container" contract).
#   - any other existing user → drop to that account (`Tier 2` finals set
#     `ENV APP_USER=luciole`). Override at runtime with `-e APP_USER=…`.
set -eo pipefail

APP_USER="${APP_USER:-}"

# ─── 1. Start sshd (idempotent) ────────────────────────────────────────────
# Create the privileged-separation dir sshd expects at runtime.
mkdir -p /run/sshd

# `service ssh start` works on Debian/Ubuntu without systemd (uses sysvinit
# fallback). Re-running it is a no-op if sshd is already up.
if command -v service >/dev/null 2>&1; then
    service ssh start >/dev/null 2>&1 || \
        echo "[entrypoint] WARN: 'service ssh start' failed (already running?)" >&2
fi

# ─── 2. Drop privileges & exec the user command ────────────────────────────
# Pass through completely when:
#   - APP_USER is empty or "root", OR
#   - the target user doesn't exist (e.g. base image booted without user.sh)
if [ -z "${APP_USER}" ] || [ "${APP_USER}" = "root" ] || \
   ! id "${APP_USER}" >/dev/null 2>&1; then
    exec "$@"
fi

# Drop privileges and replace the shell with the user command. `exec gosu`
# ensures signals (SIGTERM, SIGINT) propagate to the final process so
# `docker stop` works promptly.
if command -v gosu >/dev/null 2>&1; then
    exec gosu "${APP_USER}" "$@"
else
    # Fallback: runuser, present on every Debian/Ubuntu base.
    exec runuser -u "${APP_USER}" -- "$@"
fi
