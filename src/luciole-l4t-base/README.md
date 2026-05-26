# luciole-l4t-base

L4T (Linux for Tegra) base image for the DKUAV / Luciole project. Built on NVIDIA's L4T TensorRT image, this layer adds system tools, pip packages, and a pre-configured non-root user for all L4T-family Tier 2 images running on NVIDIA Jetson devices.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-l4t-base:latest
```

## Architecture

`arm64` only (NVIDIA Jetson)

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | `nvcr.io/nvidia/l4t-tensorrt:r10.3.0-devel` (Python + TensorRT pre-installed, arm64) |
| **System tools** | wget, vim, git, git-lfs, curl, zip/unzip, tmux, screen, htop, tree, parallel, rsync, build-essential, ninja-build, GDB, libssl, iputils, libgflags, libgoogle-glog, GTest / GMock, libopencv |
| **Python** | Provided by base image; additional pip packages added via Aliyun mirror: uv, pytest suite, FastAPI, pybind11, OpenCV, pandas, numpy, loguru, and more |
| **GUI** | WSLg support (dbus-x11, CJK fonts, Mesa, PulseAudio) |
| **Mirrors** | Aliyun apt mirror + Aliyun PyPI mirror |
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
| `USERNAME` | `luciole` | Non-root user name |
| `USER_UID` | `1000` | User UID |
| `USER_GID` | `1000` | User GID |

## Quick Start

```bash
docker pull ghcr.io/dkuav/luciole-l4t-base:latest
docker run -it --rm --runtime nvidia ghcr.io/dkuav/luciole-l4t-base:latest bash
```

### Local Build (arm64 host required)

```bash
cd src/luciole-l4t-base
docker compose build
```

Or from the repo root:

```bash
docker build -f src/luciole-l4t-base/Dockerfile -t luciole-l4t-base .
```

## Notes

- This is a **Tier 1 base image** for the L4T (Jetson) family. Published to GHCR and used as `FROM ghcr.io/dkuav/luciole-l4t-base:latest` in [`luciole-humble-l4t-dev`](../luciole-humble-l4t-dev/README.md) and [`luciole-humble-l4t-runtime`](../luciole-humble-l4t-runtime/README.md).
- Python installation is skipped (`02-python-install.sh`) because `l4t-tensorrt:r10.3.0-devel` already ships Python.
- **arm64 only** — this image is not built for amd64. CI uses native `ubuntu-24.04-arm` runners.
- No ROS 2, cmake, clang, or devshell — those are added in the Tier 2 final images.
- If the requested UID/GID is already occupied in the base image, the old user is removed automatically.
