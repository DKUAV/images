#!/bin/bash

# Install rpclib v2.3.0 from source. Used by both dev and runtime images.

set -euo pipefail

RPCLIB_VERSION_VAL=${RPCLIB_VERSION:-v2.3.0}


git clone https://github.com/rpclib/rpclib.git
cd rpclib
git checkout ${RPCLIB_VERSION_VAL}
git submodule update --init --recursive --depth 1
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
cmake --install build
