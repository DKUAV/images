# syntax=docker/dockerfile:1.4
# Tier 2 final: CUDA/PyTorch runtime environment with ROS2 (no devshell)
# FROM: ghcr.io/dkuav/luciole-cuda-base (pytorch:24.10-py3 + system + pip + cmake + user)

ARG BASE_TAG=latest
FROM ghcr.io/dkuav/luciole-cuda-base:${BASE_TAG}

COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

ARG ROS_DISTRO=humble
ARG ROS_TARGET=ros-base
RUN /tmp/scripts/ros2.sh

ARG USERNAME=luciole

USER root

# Switch apt + pip sources to Aliyun mirrors as the FINAL step, so users in
# China get fast installs after pulling. Build itself keeps using upstream
# sources (this script runs after every apt/pip install in ros2.sh etc.).
RUN /tmp/scripts/finalize-mirror.sh

RUN rm -rf /tmp/scripts

# Refresh the dynamic linker cache for libs added by ros2.sh above. Base
# already registered NVIDIA vendor .so paths; see docs/ld-cache-notes.md for
# why this remains necessary on Tier 2 images.
RUN ldconfig

USER ${USERNAME}
WORKDIR /home/${USERNAME}
