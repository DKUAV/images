#!/bin/bash
# Minimal system bootstrap: apt upgrade, timezone, locale.
# Developer CLI tools are installed separately by dev-tools.sh, and GUI / WSLg
# deps by wslg.sh, to keep each layer's cache independent.
set -euo pipefail

TZ_VAL=${TZ:-Asia/Shanghai}
SYSTEM_UPGRADE_VAL=${SYSTEM_UPGRADE:-true}

usage() {
    cat <<'EOF'
Usage: system.sh [--timezone <zone>] [--upgrade <true|false>]

Options:
  --timezone <zone>       Time zone (default: TZ or Asia/Shanghai)
  --upgrade <true|false>  Upgrade installed packages (default: SYSTEM_UPGRADE or true)
  -h, --help              Show this help
EOF
}
if ! PARSED=$(getopt -o h -l help,timezone:,upgrade: -n "$(basename "$0")" -- "$@"); then
    usage >&2
    exit 64
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        --timezone) TZ_VAL="$2"; shift 2 ;;
        --upgrade) SYSTEM_UPGRADE_VAL="$2"; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        --) shift; break ;;
    esac
done
if [ "$#" -ne 0 ]; then
    echo "system.sh: unexpected positional arguments: $*" >&2
    usage >&2
    exit 64
fi

# Prepare apt and configure the system locale and time zone.

chmod 777 /tmp

apt-get update
if [ "${SYSTEM_UPGRADE_VAL}" = "true" ]; then
    apt-get -y upgrade
fi
apt-get -y install tzdata lsb-release wget software-properties-common gnupg locales

ln -snf /usr/share/zoneinfo/${TZ_VAL} /etc/localtime
echo ${TZ_VAL} > /etc/timezone
locale-gen en_US.UTF-8

rm -rf /var/lib/apt/lists/*
