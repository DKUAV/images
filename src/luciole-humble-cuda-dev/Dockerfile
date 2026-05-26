# syntax=docker/dockerfile:1.4
# Tier 2 final: CUDA/PyTorch dev environment with ROS2, devtools and full devshell
# FROM: ghcr.io/dkuav/luciole-cuda-base (pytorch:24.10-py3 + system + pip + user)

ARG BASE_TAG=latest
FROM ghcr.io/dkuav/luciole-cuda-base:${BASE_TAG}

COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

ARG ROS_DISTRO=humble
ARG ROS_TARGET=desktop
RUN /tmp/scripts/04-ros2.sh

ARG CMAKE_VERSION=4.3.2
RUN /tmp/scripts/05-cmake.sh

RUN /tmp/scripts/06-clang.sh
RUN /tmp/scripts/07-dotnet.sh

ARG USERNAME=luciole
USER ${USERNAME}
WORKDIR /home/${USERNAME}

RUN /tmp/scripts/09-devshell.sh

USER root
RUN rm -rf /tmp/scripts

USER ${USERNAME}
WORKDIR /home/${USERNAME}
