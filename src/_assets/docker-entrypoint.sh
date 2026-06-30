#!/bin/bash
# Container entrypoint shared by every Tier 2 final image (and inherited from
# the Tier 1 base). Single responsibility: bring sshd up at runtime, then exec
# the user-supplied command.
#
# Privilege model: this entrypoint runs as whatever user the image declared via
# its trailing `USER` directive.
#   - Tier 1 base   → no `USER`, so it's root (base is a build-stone, and smoke
#     tests invoke `bash -lc '...'` overriding CMD; entrypoint is exercised but
#     irrelevant there).
#   - Tier 2 finals → `USER <appuser>` (luciole). The entrypoint uses luciole's
#     passwordless sudo (NOPASSWD:ALL from user.sh) to start sshd, then execs
#     the user command AS luciole — no gosu needed since PID 1 is already luciole.
#     Critically, this means overriding ENTRYPOINT with `docker run --entrypoint`
#     STILL leaves the container running as luciole (root is opt-in via sudo).
set -eo pipefail

# Start sshd using sudo (this entrypoint runs as the non-root user thanks to
# the image's `USER <appuser>` directive). luciole has NOPASSWD:ALL via
# sudoers, so `sudo -n service ssh start` works without a password. Doing it
# here (instead of relying on a root entrypoint + gosu) keeps the container's
# default identity as the non-root user even if someone overrides ENTRYPOINT
# with `docker run --entrypoint …` — i.e. privilege is the default, root is
# opt-in via explicit sudo.
#
# Idempotent: `/run/sshd` is tmpfs (empty on every boot) so create it first;
# `service ssh start` is a no-op if sshd is already up.
sudo -n mkdir -p /run/sshd 2>/dev/null || true
sudo -n service ssh start >/dev/null 2>&1 \
    || echo "[entrypoint] WARN: 'sudo service ssh start' failed (already running?)" >&2

# Privilege drop is NOT needed here — the image's `USER <appuser>` directive
# already makes PID 1 run as the non-root user. Just exec the user command so
# signals (SIGTERM, …) propagate directly (`docker stop` is prompt).
exec "$@"
