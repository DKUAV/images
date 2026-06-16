# syntax=docker/dockerfile:1.4
# Tier 2 final: L4T runtime environment with ROS2 and cmake (no devshell)
# FROM: ghcr.io/dkuav/luciole-l4t-base (l4t-tensorrt:r10.3.0-devel + system + pip + user)
# Architecture: arm64 only

ARG BASE_TAG=latest
FROM ghcr.io/dkuav/luciole-l4t-base:${BASE_TAG}

COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

ARG ROS_DISTRO=humble
ARG ROS_TARGET=desktop
RUN /tmp/scripts/ros2.sh

ARG CMAKE_VERSION=4.3.2
RUN /tmp/scripts/cmake.sh

RUN rm -rf /tmp/scripts

ARG USERNAME=luciole
USER ${USERNAME}
WORKDIR /home/${USERNAME}
