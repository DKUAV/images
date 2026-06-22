# luciole-cuda-base

CUDA/PyTorch base image for the DKUAV / Luciole project. Built on NVIDIA's official PyTorch image, this layer adds system tools, pip packages, and a pre-configured non-root user for all CUDA-family Tier 2 images. Targets both amd64 (x86_64 workstations) and arm64 (NVIDIA Jetson).

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-cuda-base:latest
```

## Architecture

`amd64` + `arm64`

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | `nvcr.io/nvidia/pytorch:24.10-py3` (Python + PyTorch + CUDA pre-installed) |
| **System tools** | wget, vim, git, git-lfs, curl, zip/unzip, tmux, screen, htop, tree, parallel, rsync, build-essential, ninja-build, GDB, libssl, iputils, libgflags, libgoogle-glog, GTest / GMock |
| **Python** | Provided by base image; additional pip packages added during build (uv, pytest suite, FastAPI, pybind11, pandas, numpy, loguru, and more) |
| **OpenCV** | C++: apt `libopencv-dev` 4.5.4 (FFMPEG + GStreamer). Python: pip `opencv-contrib-python` (bundles its own static FFMPEG). NVIDIA's incomplete OpenCV 4.7.0 from the base image is quarantined under `/usr/local/lib/nvidia-opencv-4.7.0.disabled/` so C++ `find_package(OpenCV)` resolves to the apt build. See [`docs/opencv-status.md`](../../docs/opencv-status.md) |
| **Build tools** | CMake 4.3.2 (binary release) |
| **GUI** | WSLg support (dbus-x11, CJK fonts, Mesa, PulseAudio) |
| **Mirrors** | This **base** image keeps the default Ubuntu / PyPI sources (build-time inclusively). The downstream Tier 2 finals (`luciole-cuda-dev`, `luciole-cuda-runtime`) flip the persisted sources to Aliyun as their final build step. |
| **Timezone** | `Asia/Shanghai` (overridable via `TZ`) |

## Default User

| Setting | Value |
|---------|-------|
| Username | `luciole` |
| UID / GID | `1000` / `1000` |
| sudo | passwordless |

## Build Arguments

| ARG | Default | Description |
|-----|---------|-------------|
| `TZ` | `Asia/Shanghai` | Timezone |
| `CMAKE_VERSION` | `4.3.2` | CMake version to install |
| `USERNAME` | `luciole` | Non-root user name |
| `USER_UID` | `1000` | User UID |
| `USER_GID` | `1000` | User GID |

## Quick Start

```bash
docker pull ghcr.io/dkuav/luciole-cuda-base:latest
docker run -it --rm --gpus all ghcr.io/dkuav/luciole-cuda-base:latest bash
```

### Local Build

```bash
cd src/luciole-cuda-base
docker compose build
```

Or from the repo root:

```bash
docker build -f src/luciole-cuda-base/Dockerfile -t luciole-cuda-base .
```

## Notes

- This is a **Tier 1 base image**. Published to GHCR and used as `FROM ghcr.io/dkuav/luciole-cuda-base:latest` in [`luciole-cuda-dev`](../luciole-cuda-dev/README.md) and [`luciole-cuda-runtime`](../luciole-cuda-runtime/README.md).
- Python installation is skipped (`python-install.sh`) because `pytorch:24.10-py3` already ships Python.
- CMake is pre-installed here so both Tier 2 images share one source of truth for the build-tool version.
- No ROS 2, clang, or devshell — those are added in the Tier 2 final images.
- **OpenCV replacement**: NVIDIA's `pytorch:24.10-py3` ships a custom-built OpenCV 4.7.0 under `/usr/local/lib` with all video decoders (FFMPEG, GStreamer) disabled. `opencv.sh` quarantines it and installs apt's `libopencv-dev` 4.5.4 with full backends for C++ (`find_package(OpenCV)`). Python `import cv2` keeps using the pip `opencv-contrib-python` wheel, which bundles its own FFMPEG and is independent of the C++ OpenCV. See [`docs/opencv-status.md`](../../docs/opencv-status.md) for the full analysis.
- **ld.so.cache registration**: NVIDIA's NGC images pre-register HPC-X (and other `/opt` vendor) `.so` paths in `ld.so.conf.d` **on amd64 only**. Without registration, `ldconfig` doesn't scan those paths and dlopen-heavy imports such as `import torch` fail on arm64 with `undefined Symbol: ucs_config_doc_nop`. The Dockerfile's final step dynamically discovers every directory under the NVIDIA vendor roots that contains a `.so`, writes them to `/etc/ld.so.conf.d/zz-ngc-extra.conf`, and runs `ldconfig` once. See [`docs/ld-cache-notes.md`](../../docs/ld-cache-notes.md) for the full root-cause analysis (including why Tier 2 images worked by accident).
- If the requested UID/GID is already occupied in the base image, the old user is removed automatically.
