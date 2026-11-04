# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

ARG BASE_TAG=2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12
ARG BASE_IMAGE=ghcr.io/dkuav/luciole-ascend:${BASE_TAG}
FROM ${BASE_IMAGE}

USER root

COPY src/ascend-peft/requirements.txt /tmp/image-scripts/peft-requirements.txt
COPY --chmod=0755 vendor/image-kit/scripts/python/ascend-python-packages.sh /tmp/image-scripts/ascend-python-packages.sh
RUN --mount=type=cache,target=/tmp/pip-cache,mode=0777 \
    PIP_CACHE_DIR=/tmp/pip-cache \
    /tmp/image-scripts/ascend-python-packages.sh --requirements /tmp/image-scripts/peft-requirements.txt

COPY --chmod=0755 vendor/image-kit/scripts/system/finalize-mirror.sh /tmp/image-scripts/finalize-mirror.sh
RUN /tmp/image-scripts/finalize-mirror.sh --mirror upstream \
    && rm -rf /tmp/image-scripts
