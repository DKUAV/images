#!/bin/bash
# Build the Ascend backend while preserving the parent image's Python packages.
# Run as root; use CANN's installed AscendNPU-IR compiler at runtime.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: install-triton-ascend.sh

Options:
  -h, --help  Show this help
EOF
}

if ! PARSED=$(getopt -o h -l help -n "$(basename "$0")" -- "$@"); then
    usage >&2
    exit 64
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        --) shift; break ;;
    esac
done
if [ "$#" -ne 0 ]; then
    usage >&2
    exit 64
fi

# This revision uses unpinned runtime dependencies, unlike the release wheels.
TRITON_ASCEND_REVISION=b3c899b8de4a1061d93f710262ef46e61e4ab4a0
# shellcheck disable=SC1091
source /etc/profile.d/ascend-dev.sh
command -v bishengir-compile

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    clang-15 lld-15 zlib1g-dev
rm -rf /var/lib/apt/lists/*

BUILD_DIRECTORY=$(mktemp -d)
trap 'rm -rf "${BUILD_DIRECTORY}"' EXIT
SOURCE_DIRECTORY="${BUILD_DIRECTORY}/source"
git init "${SOURCE_DIRECTORY}"
git -C "${SOURCE_DIRECTORY}" remote add origin https://github.com/triton-lang/triton-ascend.git
git -C "${SOURCE_DIRECTORY}" fetch --depth 1 origin "${TRITON_ASCEND_REVISION}"
git -C "${SOURCE_DIRECTORY}" checkout --detach FETCH_HEAD
# Only the pinned IR dialect sources are needed; CANN supplies the compiler tools.
git -C "${SOURCE_DIRECTORY}" submodule update --init --depth 1 -- third_party/ascend/AscendNPU-IR

# Upstream invokes unversioned compiler names. Keep these aliases build-local.
mkdir "${BUILD_DIRECTORY}/bin"
ln -s /usr/bin/clang-15 "${BUILD_DIRECTORY}/bin/clang"
ln -s /usr/bin/clang++-15 "${BUILD_DIRECTORY}/bin/clang++"
ln -s /usr/bin/lld-15 "${BUILD_DIRECTORY}/bin/lld"
ln -s /usr/bin/ld.lld-15 "${BUILD_DIRECTORY}/bin/ld.lld"

# PEP 517 isolation supplies CMake <4 without replacing the image's CMake 4.
# --no-deps only limits wheel construction; installation below resolves all deps.
PATH="${BUILD_DIRECTORY}/bin:${PATH}" \
    TRITON_HOME="${BUILD_DIRECTORY}" \
    TRITON_BUILD_WITH_CCACHE=OFF \
    TRITON_BUILD_WITH_CLANG_LLD=ON \
    TRITON_BUILD_NPUIR=OFF \
    TRITON_BUILD_PROTON=OFF \
    TRITON_BUILD_TD=OFF \
    MAX_JOBS=2 TRITON_PARALLEL_LINK_JOBS=1 \
    python3 -m pip wheel --no-deps --wheel-dir "${BUILD_DIRECTORY}/wheels" "${SOURCE_DIRECTORY}"

python3 -m pip install --break-system-packages \
    --constraint /opt/image-python/base-constraints.txt \
    "${BUILD_DIRECTORY}"/wheels/triton_ascend-*.whl
/usr/local/bin/ascend-pip-check
