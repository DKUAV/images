#!/bin/bash
# Install a fully-featured OpenCV from apt and quarantine the OpenCV 4.7.0
# shipped by the NVIDIA base image, which was built without FFMPEG, GStreamer
# or CUDA video-I/O backends.
#
# Why this is needed:
#   nvcr.io/nvidia/pytorch:24.10-py3 ships a custom-built OpenCV 4.7.0 under
#   /usr/local/lib with all video decoders disabled. CMake's find_package and
#   the dynamic linker both prefer /usr/local over /usr/lib, so any C++ target
#   built with find_package(OpenCV) silently links against the broken 4.7.0.
#
# What this script does:
#   1. Installs libopencv-dev from apt (Ubuntu 4.5.4, FFMPEG + GStreamer
#      enabled) into /usr/lib — used by C++ targets via find_package(OpenCV).
#   2. Moves NVIDIA's 4.7.0 shared libs under a sibling .disabled/ directory
#      (kept for reversibility, never deleted) and removes the CMake / pkg-config
#      / header entries that would otherwise cause find_package(OpenCV) to still
#      resolve to 4.7.0.
#   3. Refreshes ldconfig and self-verifies the C++ library resolution.
#
# This script only touches the C++ OpenCV and quarantines NVIDIA's dirty Python bindings. 
# The actual Python cv2 pip installation is owned solely by pip-packages.sh.
#
# Run as root. Currently called only by luciole-cuda-base.
set -euo pipefail

DISABLED_DIR=/usr/local/lib/nvidia-opencv-4.7.0.disabled

echo "=== apt: install libopencv-dev (4.5.4, ffmpeg + gstreamer) for C++ find_package(OpenCV) ==="
apt-get update
apt-get install -y --no-install-recommends libopencv-dev
rm -rf /var/lib/apt/lists/*

echo "=== Quarantine NVIDIA's OpenCV 4.7.0 from /usr/local/lib ==="
mkdir -p "${DISABLED_DIR}/lib/cmake" "${DISABLED_DIR}/lib/pkgconfig" "${DISABLED_DIR}/include"

# Move the shared libraries (.so / .so.407 / .so.4.7.0) out of the ld.so path.
find /usr/local/lib -maxdepth 1 -name 'libopencv_*.so*' -print0 \
    | xargs -0 -r mv -t "${DISABLED_DIR}/lib"

# CMake find_package(OpenCV) entry point: move it so it doesn't resolve to 4.7.0.
mv /usr/local/lib/cmake/opencv4 "${DISABLED_DIR}/lib/cmake/" || true
# pkg-config entry point: same reasoning.
mv /usr/local/lib/pkgconfig/opencv4.pc "${DISABLED_DIR}/lib/pkgconfig/" || true
mv /usr/local/lib/pkgconfig/opencv.pc "${DISABLED_DIR}/lib/pkgconfig/" || true
# Public headers shipped by NVIDIA's build.
mv /usr/local/include/opencv4 "${DISABLED_DIR}/include/" || true

# Quarantine the mixed Python cv2 directory.
# The NVIDIA base image places a custom __init__.py and cv2.cpython-*.so in dist-packages/cv2.
# We must quarantine the entire dirty directory so that later, when pip-packages.sh installs
# the pip wheel, it does so in a clean environment without import recursion loops.
echo "=== Quarantining NGC Python cv2 directory ==="
mkdir -p "${DISABLED_DIR}/python"
for py_cv2 in /usr/local/lib/python3.*/dist-packages/cv2; do
    if [ -d "$py_cv2" ]; then
        mv "$py_cv2" "${DISABLED_DIR}/python/" || true
    fi
done

echo "=== Refresh ld.so cache ==="
ldconfig

echo "=== Verification ==="
echo "-- apt libopencv-dev (expected: 4.5.4):"
dpkg -l | grep libopencv-dev || echo "  (not found)"
echo "-- NVIDIA OpenCV still in /usr/local/lib (expected: none):"
ls /usr/local/lib/libopencv_*.so* 2>/dev/null || echo "  (none)"
echo "-- Quarantined 4.7.0 libraries:"
ls "${DISABLED_DIR}/lib" 2>/dev/null | head -n 5 || echo "  (none)"

echo "=== opencv.sh done ==="
