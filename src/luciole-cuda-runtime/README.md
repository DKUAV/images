# luciole-cuda-runtime

Lightweight CUDA/PyTorch runtime container with ROS 2 Humble and CMake. No interactive dev tools, devshell, or C++ toolchain extensions. Intended for deployment and CI pipelines on amd64 workstations and arm64 (Jetson) boards with NVIDIA GPU support.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-cuda-runtime:latest
```

## Architecture

`amd64` + `arm64`

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | [`ghcr.io/dkuav/luciole-cuda-base`](../luciole-cuda-base/README.md) (system tools, PyTorch/CUDA, pip packages, user) |
| **ROS 2** | Humble Base (`ros-humble-base`) + `colcon`, `rosdep`, `rosinstall-generator` |
| **Build tools** | CMake 4.3.2 (binary release) |

> **Not included**: clang/LLVM, .NET SDK, devshell (zsh, neovim, oh-my-zsh, etc.)

## Default User

| Setting | Value |
|---------|-------|
| Username | `luciole` |
| UID / GID | `1000` / `1000` |
| sudo | passwordless |

## Build Arguments

| ARG | Default | Description |
|-----|---------|-------------|
| `ROS_DISTRO` | `humble` | ROS 2 distribution |
| `ROS_TARGET` | `base` | ROS 2 install target (`desktop` / `base`) |
| `CMAKE_VERSION` | `4.3.2` | CMake version to install |
| `USERNAME` | `luciole` | Non-root user name |

## Quick Start

### Pull from Registry

```bash
docker pull ghcr.io/dkuav/luciole-cuda-runtime:latest
docker run -it --rm --gpus all ghcr.io/dkuav/luciole-cuda-runtime:latest bash
```

### Local Build

```bash
cd src/luciole-cuda-runtime
docker compose build
```

Or from the repo root:

```bash
docker build -f src/luciole-cuda-runtime/Dockerfile -t luciole-cuda-runtime .
```

## ROS 2 Setup

ROS 2 is installed but **not sourced** automatically. Source it manually before use:

```bash
source /opt/ros/humble/setup.bash
```

## Notes

- This is a **Tier 2 final image** that depends on `luciole-cuda-base`.
- Supports both `amd64` (x86_64 workstations) and `arm64` (NVIDIA Jetson).
- No devshell — the default shell is `bash`. The `load_ros` alias and zsh configuration are not available.
- Suitable for CI pipelines, batch inference, or any deployment scenario that does not need interactive dev tools.
