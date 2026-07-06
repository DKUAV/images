#!/bin/bash

# Install rpclib v2.3.0 from source. Used by both dev and runtime images.

set -euo pipefail

RPCLIB_VERSION_VAL=${RPCLIB_VERSION:-v2.3.0}

cd /tmp

git clone --depth 1 --branch ${RPCLIB_VERSION_VAL} https://github.com/rpclib/rpclib.git
cd rpclib

git submodule update --init --recursive --depth 1

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DRPCLIB_CXX_STANDARD=14

cmake --build build -j"$(nproc)"
cmake --install build
