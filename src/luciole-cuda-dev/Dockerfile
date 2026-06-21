# syntax=docker/dockerfile:1.4
# Tier 2 final: CUDA/PyTorch dev environment with ROS2, devtools and full devshell
# FROM: ghcr.io/dkuav/luciole-cuda-base (pytorch:24.10-py3 + system + pip + cmake + user)

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

# Rebuild the dynamic linker cache after every apt/pip step above (ros2.sh,
# clang.sh, devshell.sh, finalize-mirror.sh installs). Base already did one
# ldconfig but these later layers added new libs; refresh so torch's dlopen path
# matches the final .so state.
RUN ldconfig

USER ${USERNAME}
WORKDIR /home/${USERNAME}
