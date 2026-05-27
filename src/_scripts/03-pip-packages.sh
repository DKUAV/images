#!/bin/bash
# Install pip packages.
# Runs on ALL base images (including those that already ship with Python).
set -euo pipefail

# pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/

pip3 install --no-cache-dir setuptools pandas numpy ipython
pip3 install --no-cache-dir pytest pytest-xdist pytest-html pytest-mock
pip3 install --no-cache-dir pytest-randomly pytest-timeout coverage pytest-cov filelock
pip3 install --no-cache-dir pre-commit rich BeautifulSoup4 allure-pytest
pip3 install --no-cache-dir plottable matplotlib opencv_python openpyxl jira python-gitlab
pip3 install --no-cache-dir flake8 black ruff mypy delegator.py build
pip3 install --no-cache-dir psycopg2-binary peewee python-calamine
pip3 install --no-cache-dir loguru fastapi aiofiles "uvicorn[standard]" python-multipart "celery[redis]"
pip3 install --no-cache-dir "pybind11[global]"
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh
