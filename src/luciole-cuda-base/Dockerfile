# syntax=docker/dockerfile:1.4
# Tier 1 base: nvcr.io/nvidia/pytorch:26.06-py3 (already ships Python + PyTorch + CUDA)
#              + system tools + pip packages + cmake + user
# Published as ghcr.io/dkuav/luciole-cuda-base

FROM nvcr.io/nvidia/pytorch:26.06-py3

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
ENV QT_X11_NO_MITSHM=1

ARG TZ=Asia/Shanghai

COPY src/_scripts/ /tmp/scripts/
COPY src/_assets/ /tmp/assets/
RUN chmod +x /tmp/scripts/*.sh /tmp/assets/*.sh

RUN /tmp/scripts/system.sh
# Replace NVIDIA's incomplete OpenCV 4.7.0 (no FFMPEG / GStreamer backends)
# with apt's libopencv-dev 4.5.4 (full video I/O) and install clean python cv2.
# RUN /tmp/scripts/opencv.sh
RUN /tmp/scripts/dev-tools.sh
RUN /tmp/scripts/wslg.sh
# Skip python-install.sh: Python is already provided by the base image
RUN /tmp/scripts/pip-packages.sh

# CMake binary release — shared by both Tier 2 dev and runtime images
ARG CMAKE_VERSION=4.3.2
RUN /tmp/scripts/cmake.sh

# libdatachannel for WebRTC data channels
ARG LIBDATACHANNEL_VERSION=v0.24.5
RUN /tmp/scripts/libdatachannel.sh

# rpclib for RPC over AirSim
ARG RPCLIB_VERSION=v2.3.0
RUN /tmp/scripts/rpclib.sh

# iceoryx for shared memory transport
ARG ICEORYX_VERSION=v2.0.8
RUN /tmp/scripts/iceoryx.sh

# SSH server for remote access (build-time config only; sshd is started at
# runtime by docker-entrypoint.sh).
RUN /tmp/scripts/ssh.sh

ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN /tmp/scripts/user.sh

# Install the shared entrypoint (starts sshd + drops to APP_USER).
# gosu (used for the privilege drop here) is installed via dev-tools.sh.
# Lives outside /tmp so it survives the cleanup below.
RUN install -D -m 0755 /tmp/assets/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN rm -rf /tmp/scripts /tmp/assets

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
# Base intentionally has NO trailing `USER`/`APP_USER` — its default user is
# root (inherited from the NVIDIA base) because base is a build-stone for
# Tier 2, not a runtime container for end users. Tier 2 finals set
# ENV APP_USER=luciole so the entrypoint drops to the dev account on boot.
# Explicitly clearing APP_USER here guarantees the inherited root-only contract
# even if a future Tier 2 layer forgets to set it differently.
ENV APP_USER=""
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/bash"]
