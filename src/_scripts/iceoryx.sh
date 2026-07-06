#!/bin/bash

# Install iceoryx from source. Used by both dev and runtime images.

set -euo pipefail

ICEORYX_VERSION_VAL=${ICEORYX_VERSION:-v2.0.8}

apt-get update
apt-get -y upgrade
apt-get install -y libacl1-dev libncurses5-dev

cd /tmp

git clone --depth 1 --branch ${ICEORYX_VERSION_VAL} https://github.com/eclipse-iceoryx/iceoryx.git

cd iceoryx

cmake -B build -S iceoryx_meta -DBUILD_SHARED_LIBS=ON
cmake --build build -j"$(nproc)"
sudo cmake --build build --target install

rm -rf /var/lib/apt/lists/*
