#!/bin/bash

# Install cpptrace from source. Used by both dev and runtime images.

set -euo pipefail

CPPTRACE_VERSION_VAL=${CPPTRACE_VERSION:-v1.0.4}

git clone --depth 1 --branch "${CPPTRACE_VERSION_VAL}" https://github.com/jeremy-rifkin/cpptrace.git

cd cpptrace

cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
cmake --install build
