# syntax=docker/dockerfile:1.4
# Tier 2 final: L4T dev environment with ROS2, devtools and full devshell
# FROM: ghcr.io/dkuav/luciole-l4t-base (l4t-tensorrt:r10.3.0-devel + system + pip + user)
# Architecture: arm64 only

ARG BASE_TAG=latest
FROM ghcr.io/dkuav/luciole-l4t-base:${BASE_TAG}

COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

ARG ROS_DISTRO=humble
ARG ROS_TARGET=desktop
RUN /tmp/scripts/04-ros2.sh

ARG CMAKE_VERSION=4.3.2
RUN /tmp/scripts/05-cmake.sh

RUN /tmp/scripts/06-clang.sh

ENV DOTNET_ROOT=/opt/dotnet
RUN /tmp/scripts/07-dotnet.sh

ARG USERNAME=luciole
USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN /tmp/scripts/09-devshell.sh

USER root
RUN rm -rf /tmp/scripts

USER ${USERNAME}
WORKDIR /home/${USERNAME}
