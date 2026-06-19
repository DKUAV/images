#!/bin/bash
# Switch apt + pip sources to Aliyun mirrors as the FINAL step of image build.
#
# Why this is a separate, last step:
#   - Builds run on GitHub Actions runners (US/EU), where Aliyun mirrors are
#     often *slower* than the default Ubuntu / PyPI sources. We therefore keep
#     the default sources during the whole build so every `apt-get update` /
#     `pip install` in system.sh, ros2.sh, pip-packages.sh, … uses the fastest
#     upstream available to the builder.
#   - Only after all package installation is done do we flip the *persisted*
#     sources to Aliyun, so that end users pulling the image in China get fast
#     `apt install` / `pip install` without reconfiguring anything.
#
# What this script does:
#   1. Rewrites the apt sources to Aliyun (auto-detects deb822 `.sources`
#      vs classic `.list` format; auto-detects the Ubuntu codename).
#   2. Writes a system-wide pip config pointing at the Aliyun PyPI mirror.
#
# Idempotent: safe to run multiple times. Run as root.
# Currently called at the very end of every Tier 2 final image (dev + runtime),
# AFTER all apt/pip installs are finished.
set -euo pipefail

ALIYUN_APT_HOST="mirrors.aliyun.com"
ALIYUN_PIP_URL="https://mirrors.aliyun.com/pypi/simple/"

# ─── Detect Ubuntu codename ───────────────────────────────────────────────────
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
fi
if [ -z "${CODENAME:-}" ]; then
    echo "finalize-mirror.sh: could not determine Ubuntu codename; aborting" >&2
    exit 1
fi
echo "finalize-mirror.sh: detected Ubuntu codename='${CODENAME}'"

# ─── 1. apt sources → Aliyun ──────────────────────────────────────────────────
#
# Ubuntu 24.04+ ships /etc/apt/sources.list.d/ubuntu.sources (deb822).
# Ubuntu 22.04  ships /etc/apt/sources.list (one-line) + optional .save.
# We detect which is in use and rewrite the corresponding file. The unused
# variant (if it exists) is emptied to avoid two conflicting upstreams.

deb822_file="/etc/apt/sources.list.d/ubuntu.sources"
classic_file="/etc/apt/sources.list"

write_deb822() {
    # Components present in modern Ubuntu main base image.
    cat > "$deb822_file" <<EOF
Types: deb
URIs: https://${ALIYUN_APT_HOST}/ubuntu/
Suites: ${CODENAME} ${CODENAME}-updates ${CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://${ALIYUN_APT_HOST}/ubuntu/
Suites: ${CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
}

write_classic() {
    cat > "$classic_file" <<EOF
deb https://${ALIYUN_APT_HOST}/ubuntu/ ${CODENAME} main restricted universe multiverse
deb https://${ALIYUN_APT_HOST}/ubuntu/ ${CODENAME}-updates main restricted universe multiverse
deb https://${ALIYUN_APT_HOST}/ubuntu/ ${CODENAME}-backports main restricted universe multiverse
deb https://${ALIYUN_APT_HOST}/ubuntu/ ${CODENAME}-security main restricted universe multiverse
EOF
}

if [ -f "$deb822_file" ]; then
    echo "finalize-mirror.sh: rewriting deb822 source ($deb822_file) → Aliyun"
    write_deb822
    # Ensure no conflicting classic file overrides us.
    if [ -f "$classic_file" ]; then
        cp "$classic_file" "${classic_file}.ubuntu-orig" 2>/dev/null || true
        : > "$classic_file"
    fi
elif [ -f "$classic_file" ]; then
    echo "finalize-mirror.sh: rewriting classic source ($classic_file) → Aliyun"
    write_classic
    # Back up the original (only first time) so the change is auditable.
    if [ ! -f "${classic_file}.ubuntu-orig" ]; then
        cp "$classic_file" "${classic_file}.ubuntu-orig" 2>/dev/null || true
    fi
else
    echo "finalize-mirror.sh: neither $deb822_file nor $classic_file found; leaving apt sources untouched" >&2
fi

# Verify apt still parses the new config. If not, roll back and fail loudly so
# we never publish a broken-sources image.
if ! apt-get update >/dev/null 2>&1; then
    echo "finalize-mirror.sh: apt-get update failed on the new Aliyun sources; rolling back" >&2
    if [ -f "${classic_file}.ubuntu-orig" ]; then
        cp "${classic_file}.ubuntu-orig" "$classic_file"
    fi
    rm -f "$deb822_file"
    exit 1
fi
rm -rf /var/lib/apt/lists/*

# ─── 2. pip → Aliyun PyPI mirror ──────────────────────────────────────────────
echo "finalize-mirror.sh: writing /etc/pip.conf → Aliyun PyPI mirror"
install -d -m 0755 /etc
cat > /etc/pip.conf <<EOF
[global]
index-url = ${ALIYUN_PIP_URL}
trusted-host = mirrors.aliyun.com
EOF
chmod 0644 /etc/pip.conf

echo "finalize-mirror.sh: done"
