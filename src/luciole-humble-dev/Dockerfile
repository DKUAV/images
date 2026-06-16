# syntax=docker/dockerfile:1.4
# Tier 2 final: Ubuntu dev environment with ROS2, devtools and full devshell
# FROM: ghcr.io/dkuav/luciole-base (system + Python + pip + user)

ARG BASE_TAG=latest
FROM ghcr.io/dkuav/luciole-base:${BASE_TAG}

# Build context is the repo root
COPY src/_scripts/ /tmp/scripts/
COPY src/_assets/ /tmp/assets/
RUN chmod +x /tmp/scripts/*.sh

ARG ROS_DISTRO=humble
ARG ROS_TARGET=desktop
RUN /tmp/scripts/ros2.sh

ARG CMAKE_VERSION=4.3.2
RUN /tmp/scripts/cmake.sh

RUN /tmp/scripts/clang.sh

ARG USERNAME=luciole
USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN /tmp/scripts/devshell.sh
RUN /tmp/scripts/precommit.sh

USER root
RUN rm -rf /tmp/scripts /tmp/assets

USER ${USERNAME}
WORKDIR /home/${USERNAME}
