#!/bin/bash

# Install libdatachannel v0.24.5 from source. Used by both dev and runtime images.

set -euo pipefail

LIBDATACHANNEL_VERSION_VAL=${LIBDATACHANNEL_VERSION:-v0.24.5}


git clone https://github.com/paullouisageneau/libdatachannel.git
cd libdatachannel
git checkout ${LIBDATACHANNEL_VERSION_VAL}
git submodule update --init --recursive --depth 1
cmake -B build -DUSE_GNUTLS=0 -DUSE_NICE=0 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
cmake --install build
