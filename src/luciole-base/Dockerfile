# syntax=docker/dockerfile:1.4
# Tier 1 base: Ubuntu 22.04 + system tools + Python 3.10 + pip packages + user
# Published as ghcr.io/dkuav/luciole-base

FROM mcr.microsoft.com/devcontainers/base:ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
ENV QT_X11_NO_MITSHM=1

ARG TZ=Asia/Shanghai

# Build context is the repo root; scripts are shared across all images
COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

RUN /tmp/scripts/system.sh
RUN /tmp/scripts/python-install.sh
RUN /tmp/scripts/pip-packages.sh

ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN /tmp/scripts/user.sh

RUN rm -rf /tmp/scripts

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
