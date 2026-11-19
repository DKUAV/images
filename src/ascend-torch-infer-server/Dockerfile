# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

ARG BASE_TAG=2.10.0.post7-cann9.2.0-peft-910b-ubuntu22.04-py3.12
ARG BASE_IMAGE=ghcr.io/dkuav/ascend-peft:${BASE_TAG}
FROM ${BASE_IMAGE}

USER root

COPY src/ascend-torch-infer-server/requirements.txt /tmp/image-scripts/infer-server-requirements.txt
# Protect the installed PEFT stack, including its five Triton auxiliary versions.
RUN --mount=type=cache,target=/tmp/pip-cache,mode=0777 \
    python3 -m pip list --format=freeze > /opt/image-python/infer-server-constraints.txt \
    && PIP_CACHE_DIR=/tmp/pip-cache python3 -m pip install --break-system-packages \
        --constraint /opt/image-python/infer-server-constraints.txt \
        --requirement /tmp/image-scripts/infer-server-requirements.txt \
    && /usr/local/bin/ascend-pip-check

COPY --chmod=0755 vendor/image-kit/scripts/system/finalize-mirror.sh /tmp/image-scripts/finalize-mirror.sh
RUN /tmp/image-scripts/finalize-mirror.sh --mirror upstream \
    && rm -rf /tmp/image-scripts
