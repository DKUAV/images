# syntax=docker/dockerfile:1.4
# Tier 1 base: nvcr.io/nvidia/l4t-tensorrt:r10.3.0-devel (arm64, already ships Python + TensorRT)
#              + system tools + pip packages + user
# Published as ghcr.io/dkuav/luciole-l4t-base
# Architecture: arm64 only

FROM nvcr.io/nvidia/l4t-tensorrt:r10.3.0-devel

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
ENV QT_X11_NO_MITSHM=1

ARG TZ=Asia/Shanghai

COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

RUN /tmp/scripts/system.sh
RUN /tmp/scripts/dev-tools.sh
# Skip python-install.sh: Python is already provided by the base image
RUN /tmp/scripts/pip-packages.sh

ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN /tmp/scripts/user.sh

RUN rm -rf /tmp/scripts

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
