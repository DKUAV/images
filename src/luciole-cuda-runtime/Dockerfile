# syntax=docker/dockerfile:1.4
# Tier 2 final: CUDA/PyTorch runtime environment with ROS2 (no devshell)
# FROM: ghcr.io/dkuav/luciole-cuda-base (pytorch:26.06-py3 + system + pip + cmake + user)

ARG BASE_TAG=pytorch26.06-py3
ARG BASE_IMAGE=ghcr.io/dkuav/luciole-cuda-base:${BASE_TAG}
FROM ${BASE_IMAGE}

ARG ROS_DISTRO=jazzy
ARG ROS_TARGET=ros-base
COPY --chmod=0755 vendor/image-kit/scripts/integrations/ros2.sh /tmp/scripts/ros2.sh
RUN /tmp/scripts/ros2.sh --distro "${ROS_DISTRO}" --target "${ROS_TARGET}"

ARG USERNAME=luciole

USER root

# Switch apt + pip sources to Aliyun mirrors as the FINAL step, so users in
# China get fast installs after pulling. Build itself keeps using upstream
# sources (this script runs after every apt/pip install in ros2.sh etc.).
COPY --chmod=0755 vendor/image-kit/scripts/system/finalize-mirror.sh /tmp/scripts/finalize-mirror.sh
RUN /tmp/scripts/finalize-mirror.sh --mirror aliyun

RUN rm -rf /tmp/scripts

# Refresh the dynamic linker cache for libs added by ros2.sh above. Base
# already registered NVIDIA vendor .so paths; see docs/ld-cache-notes.md for
# why this remains necessary on Tier 2 images.
RUN ldconfig

# Tell the inherited entrypoint what user we are. NOTE: with the Docker-USER +
# sudo-sshd design, the entrypoint no longer needs APP_USER itself; we keep the
# ENV for documentation / tooling that introspects it.
ENV APP_USER=${USERNAME}
ENV HOME=/home/${USERNAME}
# Real `USER` directive below — this is the actual privilege gate. The
# container boots as luciole; entrypoint uses luciole's passwordless sudo to
# start sshd, then execs the user's command as luciole. Even if someone runs
# `docker run --entrypoint bash <img>`, this USER keeps identity = luciole.
USER ${USERNAME}
WORKDIR /home/${USERNAME}
