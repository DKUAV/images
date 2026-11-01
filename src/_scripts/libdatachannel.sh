#!/bin/bash

# Install libdatachannel v0.24.5 from source. Used by both dev and runtime images.

set -euo pipefail

LIBDATACHANNEL_VERSION_VAL=${LIBDATACHANNEL_VERSION:-v0.24.5}

# Select the source revision; the environment variable remains the default.
usage() {
    echo "Usage: libdatachannel.sh [--version <revision>] [-h|--help]"
    echo "  --version <revision>  Source revision (default: LIBDATACHANNEL_VERSION or v0.24.5)"
}
if ! PARSED=$(getopt -o h -l help,version: -n "$(basename "$0")" -- "$@"); then
    usage >&2
    exit 64
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        --version) LIBDATACHANNEL_VERSION_VAL="$2"; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        --) shift; break ;;
    esac
done
if [ "$#" -ne 0 ]; then
    echo "libdatachannel.sh: unexpected positional arguments: $*" >&2
    usage >&2
    exit 64
fi

cd /tmp

git clone --depth 1 --branch ${LIBDATACHANNEL_VERSION_VAL} https://github.com/paullouisageneau/libdatachannel.git
cd libdatachannel
git submodule update --init --recursive --depth 1

cmake -B build -DUSE_GNUTLS=0 -DUSE_NICE=0 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
cmake --install build
