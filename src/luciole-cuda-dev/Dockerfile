# syntax=docker/dockerfile:1.4
# Tier 2 final: CUDA/PyTorch dev environment with ROS2, devtools and full devshell
# FROM: ghcr.io/dkuav/luciole-cuda-base (pytorch:26.06-py3 + system + pip + cmake + user)

ARG BASE_TAG=latest
FROM ghcr.io/dkuav/luciole-cuda-base:${BASE_TAG}

COPY src/_scripts/ /tmp/scripts/
COPY src/_assets/ /tmp/assets/
RUN chmod +x /tmp/scripts/*.sh

ARG ROS_DISTRO=humble
ARG ROS_TARGET=ros-base
RUN /tmp/scripts/ros2.sh

RUN /tmp/scripts/clang.sh

ARG USERNAME=luciole
USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN /tmp/scripts/devshell.sh
RUN /tmp/scripts/precommit.sh

USER root

# Switch apt + pip sources to Aliyun mirrors as the FINAL step, so users in
# China get fast installs after pulling. Build itself keeps using upstream
# sources (this script runs after every apt/pip install in devshell.sh etc.).
RUN /tmp/scripts/finalize-mirror.sh

RUN rm -rf /tmp/scripts /tmp/assets

# Refresh the dynamic linker cache for libs added by ros2.sh / clang.sh /
# devshell.sh above. Base already registered NVIDIA vendor .so paths; see
# docs/ld-cache-notes.md for why this remains necessary on Tier 2 images.
RUN ldconfig

# Tell the inherited entrypoint to drop to the dev user on boot (and keep
# sshd up). Override the inherited `CMD ["/bin/bash"]` so an interactive
# `docker run -it` lands in zsh — the dev shell this image is built around.
ENV APP_USER=${USERNAME}
USER ${USERNAME}

WORKDIR /home/${USERNAME}
CMD ["/bin/zsh"]
