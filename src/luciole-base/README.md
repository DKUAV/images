# luciole-base

Ubuntu 22.04 base image for the DKUAV / Luciole project. Provides the foundation layer — system tools, Python 3.10, pip packages, and a pre-configured non-root user — for all Ubuntu-family Tier 2 images.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-base:latest
```

## Architecture

`amd64` only

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | `mcr.microsoft.com/devcontainers/base:ubuntu22.04` |
| **System tools** | wget, vim, git, git-lfs, curl, zip/unzip, tmux, screen, htop, tree, parallel, rsync, build-essential, ninja-build, GDB, libssl, iputils, libgflags, libgoogle-glog, GTest / GMock, libopencv |
| **Python** | Python 3.10, pip (Aliyun mirror), uv, pytest suite, FastAPI, pybind11, OpenCV, pandas, numpy, loguru, and more |
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
docker pull ghcr.io/dkuav/luciole-base:latest
docker run -it --rm ghcr.io/dkuav/luciole-base:latest bash
```

### Local Build

```bash
cd src/luciole-base
docker compose build
```

Or from the repo root:

```bash
docker build -f src/luciole-base/Dockerfile -t luciole-base .
```

## Notes

- This is a **Tier 1 base image**. It is published to GHCR and used as `FROM ghcr.io/dkuav/luciole-base:latest` in [`luciole-humble-dev`](../luciole-humble-dev/README.md).
- No ROS 2, cmake, clang, or devshell are installed — those are added in the Tier 2 final images.
- If the requested UID/GID is already occupied in the base image, the old user is removed automatically before creating `luciole`.
