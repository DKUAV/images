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
#      resolve to 4.7.0. The quarantined libraries are C++/ld.so only — the
#      pip cv2 wheel is fully static and is unaffected, so Python cv2 is
#      untouched here.
#   3. Refreshes ldconfig and self-verifies the resolution.
#
# This script only touches the C++ OpenCV. Python cv2 is owned solely by
# pip-packages.sh (where the duplicate-wheel issue is fixed at the source).
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
# Keep them on disk so the change is fully reversible: moving the files back
# plus re-running ldconfig restores the upstream layout.
find /usr/local/lib -maxdepth 1 -name 'libopencv_*.so*' -print0 \
    | xargs -0 -r mv -t "${DISABLED_DIR}/lib"

# CMake find_package(OpenCV) entry point: move it so it doesn't resolve to 4.7.0.
mv /usr/local/lib/cmake/opencv4 "${DISABLED_DIR}/lib/cmake/" || true
# pkg-config entry point: same reasoning.
mv /usr/local/lib/pkgconfig/opencv4.pc "${DISABLED_DIR}/lib/pkgconfig/" || true
mv /usr/local/lib/pkgconfig/opencv.pc "${DISABLED_DIR}/lib/pkgconfig/" || true
# Public headers shipped by NVIDIA's build: move them so the compiler falls
# back to the apt headers under /usr/include/opencv4.
mv /usr/local/include/opencv4 "${DISABLED_DIR}/include/" || true

echo "=== Refresh ld.so cache ==="
ldconfig

echo "=== Verify ==="
echo "-- apt OpenCV C++ packages:"
dpkg -l | grep -E 'libopencv' || true
echo "-- NVIDIA OpenCV still in /usr/local/lib (expected: none):"
ls /usr/local/lib/libopencv_*.so* 2>/dev/null || echo "  (none)"
echo "-- Quarantined 4.7.0 libraries:"
ls "${DISABLED_DIR}/lib" 2>/dev/null | head -n 5 || echo "  (none)"
echo "-- Python cv2 (pip opencv-contrib-python wheel, static ffmpeg, unaffected by above):"
python3 -c "import cv2; print('  cv2', cv2.__version__, cv2.__file__)"
echo "-- cv2 FFMPEG backend check (FFMPEG should be YES):"
python3 - <<'PY'
import cv2
info = cv2.getBuildInformation()
for line in info.splitlines():
    if line.strip().startswith('FFMPEG') or line.strip().startswith('GStreamer'):
        print('  ' + line.rstrip())
PY

echo "=== opencv.sh done ==="
