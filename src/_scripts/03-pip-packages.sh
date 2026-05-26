#!/bin/bash
# Install pip packages.
# Runs on ALL base images (including those that already ship with Python).
set -euo pipefail

pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/

pip3 install setuptools pandas numpy ipython \
    && pip3 install pytest pytest-xdist pytest-html pytest-mock \
    && pip3 install pytest-randomly pytest-timeout coverage pytest-cov filelock \
    && pip3 install pre-commit rich BeautifulSoup4 allure-pytest \
    && pip3 install plottable matplotlib opencv_python openpyxl jira python-gitlab \
    && pip3 install flake8 black ruff mypy delegator.py build \
    && pip3 install psycopg2-binary peewee python-calamine \
    && pip3 install loguru fastapi aiofiles "uvicorn[standard]" python-multipart "celery[redis]" \
    && pip3 install "pybind11[global]" \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && pip3 cache purge
