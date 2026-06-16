#!/bin/bash
# Install a recent CMake binary release. Reads CMAKE_VERSION (default: 4.3.2).
# Used by both dev and runtime images.
set -euo pipefail

CMAKE_VERSION_VAL=${CMAKE_VERSION:-4.3.2}

ARCH=$(uname -m)
case $ARCH in
    x86_64)  CMAKE_ARCH="linux-x86_64" ;;
    aarch64) CMAKE_ARCH="linux-aarch64" ;;
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac

wget "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION_VAL}/cmake-${CMAKE_VERSION_VAL}-${CMAKE_ARCH}.tar.gz"
tar -xf "cmake-${CMAKE_VERSION_VAL}-${CMAKE_ARCH}.tar.gz" --strip-components=1 -C /usr/local
rm "cmake-${CMAKE_VERSION_VAL}-${CMAKE_ARCH}.tar.gz"
