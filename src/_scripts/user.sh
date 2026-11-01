#!/bin/bash
# Ensure the requested default user exists and configure managed non-root users.
# Options: --username, --uid, and --gid. Root is reused; no password is created.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: user.sh [--username <name>] [--uid <id>] [--gid <id>]

Options:
  --username <value>  User name (default: luciole; root reuses the existing account)
  --uid <value>       User ID (default: 1000; not applied to root)
  --gid <value>       Group ID (default: value of --uid; not applied to root)
  -h, --help          Show this help
EOF
}

USERNAME_VAL="luciole"
USER_UID_VAL="1000"
USER_GID_VAL=""

if ! PARSED=$(getopt -o h -l help,username:,uid:,gid: -n "$(basename "$0")" -- "$@"); then
    usage >&2
    exit 64
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        --username)
            USERNAME_VAL="$2"
            shift 2
            ;;
        --uid)
            USER_UID_VAL="$2"
            shift 2
            ;;
        --gid)
            USER_GID_VAL="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
    esac
done
if [ "$#" -ne 0 ]; then
    echo "user.sh: unexpected positional arguments: $*" >&2
    usage >&2
    exit 64
fi
USER_GID_VAL="${USER_GID_VAL:-${USER_UID_VAL}}"
if [[ ! "${USERNAME_VAL}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "user.sh: invalid username '${USERNAME_VAL}'" >&2
    exit 64
fi
if [[ ! "${USER_UID_VAL}" =~ ^[0-9]+$ || ! "${USER_GID_VAL}" =~ ^[0-9]+$ ]]; then
    echo "user.sh: uid and gid must be non-negative integers" >&2
    exit 64
fi

# Root is provided by the base image and must never be recreated or renumbered.
if [ "${USERNAME_VAL}" = "root" ]; then
    exit 0
fi

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
useradd --uid "${USER_UID_VAL}" --gid "${USER_GID_VAL}" --create-home \
    --shell /bin/bash "${USERNAME_VAL}"
passwd --lock "${USERNAME_VAL}"

apt-get update
apt-get install -y sudo
rm -rf /var/lib/apt/lists/*
echo "${USERNAME_VAL} ALL=(root) NOPASSWD:ALL" >/etc/sudoers.d/"${USERNAME_VAL}"
chmod 0440 /etc/sudoers.d/"${USERNAME_VAL}"

# XDG runtime dir — needed for VS Code IPC sockets and GUI apps
mkdir -p /run/user/"${USER_UID_VAL}"
chown "${USERNAME_VAL}":"${USERNAME_VAL}" /run/user/"${USER_UID_VAL}"
chmod 0700 /run/user/"${USER_UID_VAL}"
