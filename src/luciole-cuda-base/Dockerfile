# syntax=docker/dockerfile:1.4
# Tier 1 base: nvcr.io/nvidia/pytorch:26.06-py3 (already ships Python + PyTorch + CUDA)
#              + system tools + pip packages + cmake + user
# Published as ghcr.io/dkuav/luciole-cuda-base

ARG BASE_IMAGE=nvcr.io/nvidia/pytorch:26.06-py3
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
ENV QT_X11_NO_MITSHM=1

# Default editor — set in base so both Tier 2 finals inherit it; the
# update-alternatives pin in dev-tools.sh covers sudo env_reset contexts.
ENV EDITOR=vim
ENV VISUAL=vim

ARG TZ=Asia/Shanghai

COPY --chmod=0755 src/_scripts/system.sh /tmp/scripts/system.sh
RUN /tmp/scripts/system.sh
# OpenCV replacement remains disabled; dev-tools installs apt libopencv-dev.
COPY --chmod=0755 src/_scripts/dev-tools.sh /tmp/scripts/dev-tools.sh
RUN /tmp/scripts/dev-tools.sh
COPY --chmod=0755 src/_scripts/wslg.sh /tmp/scripts/wslg.sh
RUN /tmp/scripts/wslg.sh
# Skip python-install.sh: Python is already provided by the base image
COPY --chmod=0755 src/_scripts/pip-packages.sh /tmp/scripts/pip-packages.sh
RUN /tmp/scripts/pip-packages.sh

# CMake binary release — shared by both Tier 2 dev and runtime images
ARG CMAKE_VERSION=4.3.2
COPY --chmod=0755 src/_scripts/cmake.sh /tmp/scripts/cmake.sh
RUN /tmp/scripts/cmake.sh

# libdatachannel for WebRTC data channels
ARG LIBDATACHANNEL_VERSION=v0.24.5
COPY --chmod=0755 src/_scripts/libdatachannel.sh /tmp/scripts/libdatachannel.sh
RUN /tmp/scripts/libdatachannel.sh

# rpclib for RPC over AirSim
ARG RPCLIB_VERSION=v2.3.0
COPY --chmod=0755 src/_scripts/rpclib.sh /tmp/scripts/rpclib.sh
RUN /tmp/scripts/rpclib.sh

# iceoryx for shared memory transport
ARG ICEORYX_VERSION=v2.0.8
COPY --chmod=0755 src/_scripts/iceoryx.sh /tmp/scripts/iceoryx.sh
RUN /tmp/scripts/iceoryx.sh

# SSH server for remote access (build-time config only; sshd is started at
# runtime by docker-entrypoint.sh).
ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
COPY --chmod=0755 src/_scripts/ssh.sh /tmp/scripts/ssh.sh
RUN /tmp/scripts/ssh.sh

COPY --chmod=0755 src/_scripts/user.sh /tmp/scripts/user.sh
RUN /tmp/scripts/user.sh

# Install the shared entrypoint (used by every Tier 2 final too). The
# entrypoint just starts sshd (via sudo) and execs the user command; it does
# NOT take responsibility for privilege drop — that's the image's `USER`
# directive's job (see dev/runtime Dockerfiles). Lives outside /tmp so it
# survives the cleanup below.
COPY --chmod=0755 src/_assets/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN rm -rf /tmp/scripts

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
# Base intentionally has NO trailing `USER` directive — its default user is
# root (inherited from the NVIDIA base) because base is a build-stone for
# Tier 2, not a runtime container for end users. The Tier 2 finals add a
# real `USER <appuser>` directive at their own end, so the entrypoint picks
# up that identity on boot. (The entrypoint itself is privilege-agnostic: it
# uses `sudo -n` to start sshd, which works whether PID 1 is root or a sudoer.)
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/bash"]
