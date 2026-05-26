#!/bin/bash
# Install Python 3.10 from apt and bootstrap pip.
# Skip this script for base images that already ship with Python (pytorch, l4t-tensorrt).
set -euo pipefail

apt-get update \
    && apt-get install -y python3.10 python3-setuptools \
    && rm -rf /var/lib/apt/lists/*

curl -LsSf https://bootstrap.pypa.io/pip/get-pip.py | python3.10

pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/
