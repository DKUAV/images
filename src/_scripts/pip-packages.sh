#!/bin/bash
# Install pip packages.
# Runs on ALL base images (including those that already ship with Python).
set -euo pipefail

# pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/

python3 -m pip install --upgrade pip
pip3 install --no-cache-dir \
    setuptools pandas "numpy<2.0.0" ipython polars seaborn \
    pytest pytest-xdist pytest-html pytest-mock \
    pytest-randomly pytest-timeout coverage pytest-cov filelock \
    pre-commit rich BeautifulSoup4 allure-pytest \
    plottable matplotlib openpyxl \
    opencv-contrib-python \
    flake8 black ruff mypy delegator.py build \
    psycopg2-binary peewee python-calamine \
    loguru fastapi aiofiles "uvicorn[standard]" python-multipart "celery[redis]" \
    "pybind11[global]" \
    scikit-image h5py onnxruntime onnx-simplifier \
    thop lap motmetrics filterpy ultralytics

curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh
