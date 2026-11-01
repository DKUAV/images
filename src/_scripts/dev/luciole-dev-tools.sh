#!/bin/bash
# Install Luciole-specific system tools after image-kit's common developer tools.
# Run as root after the common developer tools.
set -euo pipefail

usage() {
    echo "Usage: luciole-dev-tools.sh [-h|--help]"
}
if ! PARSED=$(getopt -o h -l help -n "$(basename "$0")" -- "$@"); then
    usage >&2
    exit 64
fi
eval set -- "$PARSED"
case "$1" in
    -h | --help)
        usage
        exit 0
        ;;
    --) shift ;;
esac
if [ "$#" -ne 0 ]; then
    echo "luciole-dev-tools.sh: unexpected positional arguments: $*" >&2
    usage >&2
    exit 64
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    landscape-common
rm -rf /var/lib/apt/lists/*
