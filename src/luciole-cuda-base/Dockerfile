# syntax=docker/dockerfile:1.4
# Tier 1 base: nvcr.io/nvidia/pytorch:24.10-py3 (already ships Python + PyTorch + CUDA)
#              + system tools + pip packages + cmake + user
# Published as ghcr.io/dkuav/luciole-cuda-base

FROM nvcr.io/nvidia/pytorch:24.10-py3

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"
ENV QT_X11_NO_MITSHM=1

ARG TZ=Asia/Shanghai

COPY src/_scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

RUN /tmp/scripts/system.sh
# Replace NVIDIA's incomplete OpenCV 4.7.0 (no FFMPEG / GStreamer backends)
# with apt's libopencv-dev 4.5.4 (full video I/O) and install clean python cv2.
RUN /tmp/scripts/opencv.sh
RUN /tmp/scripts/dev-tools.sh
RUN /tmp/scripts/wslg.sh
# Skip python-install.sh: Python is already provided by the base image
RUN /tmp/scripts/pip-packages.sh

# CMake binary release — shared by both Tier 2 dev and runtime images
ARG CMAKE_VERSION=4.3.2
RUN /tmp/scripts/cmake.sh

ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN /tmp/scripts/user.sh

RUN rm -rf /tmp/scripts

# Rebuild the dynamic linker cache as the FINAL step. Earlier scripts install
# libraries into /usr/local/lib and /usr/lib (apt hf, pip wheels like
# opencv-contrib-python, NVIDIA's HPC-X under /opt/hpcx/...). Each RUN layer
# snapshots /etc/ld.so.cache, so installers run on top of a stale cache. Without
# a final ldconfig, dlopen() at runtime can resolve against a lib from the
# wrong version — e.g. torch's _C loading libucc.so.1 first before libucs.so
# provides the matching `ucs_config_doc_nop` symbol:
#   ImportError: /opt/hpcx/ucc/lib/libucc.so.1: undefined symbol: ucs_config_doc_nop
# Re-running ldconfig once here makes the cache reflect the final .so state.
RUN ldconfig

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
