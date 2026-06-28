#!/bin/bash

# Install iceoryx from source. Used by both dev and runtime images.

set -euo pipefail

ICEORYX_VERSION_VAL=${ICEORYX_VERSION:-v2.0.8}

apt-get update
apt-get -y upgrade
apt-get install -y libacl1-dev libncurses5-dev

git clone https://github.com/eclipse-iceoryx/iceoryx.git

cd iceoryx
git checkout ${ICEORYX_VERSION_VAL}
cmake -Bbuild -Hiceoryx_meta

cmake --build build
cmake --build build --target install

rm -rf /var/lib/apt/lists/*
