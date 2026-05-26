# syntax=docker/dockerfile:1.4
# Tier 1 base: nvcr.io/nvidia/pytorch:24.10-py3 (already ships Python + PyTorch + CUDA)
#              + system tools + pip packages + user
# Published as ghcr.io/dkuav/luciole-cuda-base

FROM nvcr.io/nvidia/pytorch:24.10-py3

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
ENV QT_X11_NO_MITSHM=1

ARG TZ=Asia/Shanghai

COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

RUN /tmp/scripts/01-system.sh
# Skip 02-python-install.sh: Python is already provided by the base image
RUN /tmp/scripts/03-pip-packages.sh

ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN /tmp/scripts/08-user.sh

RUN rm -rf /tmp/scripts

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
