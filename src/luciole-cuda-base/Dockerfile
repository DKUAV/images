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

# Work around a real NVIDIA NGC pytorch:24.10-py3 (arm64) bug: HPC-X v2.20
# bundles UCC 1.4.0 against UCX 1.17.0, but libucc.so references
# `ucs_config_doc_nop` — a symbol added only in UCX 1.18+. On arm64 there is
# therefore NO libucs anywhere on disk that exports that symbol. When torch's
# `_C` is dlopened, the linker finds libucc.so.1 via `/opt/hpcx/ucc/lib`
# (pre-registered by NVIDIA in /etc/ld.so.conf.d/hpcx.conf) and aborts with:
#   ImportError: /opt/hpcx/ucc/lib/libucc.so.1: undefined symbol: ucs_config_doc_nop
# torch itself doesn't need HPC-X's libucc/libucx — it just trips over them
# because they are on the global ld.so search path. Fix = unregister those two
# HPC-X comm-lib paths from the NVIDIA-provided hpcx.conf AND never put them
# into our own zz-ngc-extra.conf. Any real MPI/UCC user will `source
# /opt/hpcx/.../hpcx-init.sh` which sets LD_LIBRARY_PATH explicitly and
# restores them at runtime. amd64 doesn't have the version skew, so the sed
# is a no-op there. See docs/ld-cache-notes.md for the full diagnosis.
RUN sed -i -E '\@^/opt/hpcx/(ucc|ucx)/lib$@d' \
        /etc/ld.so.conf.d/hpcx.conf 2>/dev/null || true \
    ; find \
        /opt/hpcx/hcoll \
        /opt/hpcx/ompi \
        /opt/hpcx/sharp \
        /opt/hpcx/nccl_rdma_sharp_plugin \
        /opt/tensorrt \
        /opt/nvidia \
        /opt/ros \
        /usr/local/lib \
        -type f -name '*.so*' 2>/dev/null \
        | xargs -r dirname \
        | sort -u > /etc/ld.so.conf.d/zz-ngc-extra.conf \
    ; ldconfig

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
