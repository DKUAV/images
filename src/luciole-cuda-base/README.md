# luciole-cuda-base

CUDA/PyTorch base image for the DKUAV / Luciole project. Built on NVIDIA's official PyTorch image, this layer adds system tools, pip packages, and a pre-configured non-root user for all CUDA-family Tier 2 images.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-cuda-base:latest
```

## Architecture

`amd64` only

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | `nvcr.io/nvidia/pytorch:24.10-py3` (Python + PyTorch + CUDA pre-installed) |
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

- This is a **Tier 1 base image**. Published to GHCR and used as `FROM ghcr.io/dkuav/luciole-cuda-base:latest` in [`luciole-humble-cuda-dev`](../luciole-humble-cuda-dev/README.md) and [`luciole-humble-cuda-runtime`](../luciole-humble-cuda-runtime/README.md).
- Python installation is skipped (`python-install.sh`) because `pytorch:24.10-py3` already ships Python.
- No ROS 2, cmake, clang, or devshell — those are added in the Tier 2 final images.
- If the requested UID/GID is already occupied in the base image, the old user is removed automatically.
