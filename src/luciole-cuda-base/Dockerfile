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
RUN chmod +x /tmp/scripts/*.sh

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

ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
RUN /tmp/scripts/user.sh

RUN rm -rf /tmp/scripts

# Work around an arm64-only NVIDIA NGC pytorch:26.06-py3 bug: HPC-X v2.20
# bundles UCC 1.4 against UCX 1.17, but UCC 1.4 references `ucs_config_doc_nop`
# (a symbol added only in UCX 1.18+). On arm64 there is therefore NO libucs
# anywhere on disk that can satisfy libucc — torch's `_C` dlopen fails with:
#   ImportError: /opt/hpcx/ucc/lib/libucc.so.1: undefined symbol: ucs_config_doc_nop
#
# torch itself doesn't actually need HPC-X's libucc/libucx (its `_C` references
# libucc symbolically but the HPC-X copy is broken). Fix = on arm64 only, strip
# `/opt/hpcx/{ucc,ucx}/lib` from NVIDIA's hpcx.conf so torch's dlopen search
# chain can't find the broken copy.
#
# amd64 is UNTOUCHED by this gate: there the HPC-X UCX/UCC pair is internally
# consistent and torch really does link libucc — removing the registration
# would crash amd64 with "libucc.so.1: cannot open shared object file".
#
# Tier 2 images inherit this fix from base. Real MPI/UCC users on arm64 still
# have HPC-X at runtime via `source /opt/hpcx/.../hpcx-init.sh` which exports
# LD_LIBRARY_PATH explicitly. See docs/ld-cache-notes.md for the full diagnosis.
RUN set -e; \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        sed -i -E '\@^/opt/hpcx/(ucc|ucx)/lib$@d' /etc/ld.so.conf.d/hpcx.conf; \
    fi; \
    ldconfig

ENV XDG_RUNTIME_DIR=/run/user/${USER_UID}
