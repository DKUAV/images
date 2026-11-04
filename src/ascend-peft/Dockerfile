# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

ARG BASE_TAG=2.10.0.post7-cann9.2.0-910b-ubuntu22.04-py3.12
ARG BASE_IMAGE=ghcr.io/dkuav/luciole-ascend:${BASE_TAG}
FROM ${BASE_IMAGE}

USER root

COPY src/ascend-peft/requirements.txt /tmp/image-scripts/peft-requirements.txt
# Only these five auxiliary packages may change from the recorded vendor versions.
RUN --mount=type=cache,target=/tmp/pip-cache,mode=0777 \
    awk -F '==' 'tolower($1) !~ /^(attrs|numpy|scipy|decorator|psutil)$/' \
        /opt/image-python/base-constraints.txt > /opt/image-python/peft-constraints.txt \
    && PIP_CACHE_DIR=/tmp/pip-cache python3 -m pip install --break-system-packages \
        --constraint /opt/image-python/peft-constraints.txt \
        --requirement /tmp/image-scripts/peft-requirements.txt \
    && /usr/local/bin/ascend-pip-check

COPY --chmod=0755 vendor/image-kit/scripts/system/finalize-mirror.sh /tmp/image-scripts/finalize-mirror.sh
RUN /tmp/image-scripts/finalize-mirror.sh --mirror upstream \
    && rm -rf /tmp/image-scripts
