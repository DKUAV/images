# luciole-humble-l4t-runtime

Lightweight L4T runtime container (arm64) with ROS 2 Humble and CMake. No interactive dev tools, devshell, or C++ toolchain extensions. Designed for NVIDIA Jetson deployment and CI pipelines.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-humble-l4t-runtime:latest
```

## Architecture

`arm64` only (NVIDIA Jetson)

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | [`ghcr.io/dkuav/luciole-l4t-base`](../luciole-l4t-base/README.md) (system tools, TensorRT/Python, pip packages, user) |
| **ROS 2** | Humble Desktop (`ros-humble-desktop`) + `colcon`, `rosdep`, `rosinstall-generator` |
| **Build tools** | CMake 4.3.2 (binary release, aarch64) |

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
| `ROS_TARGET` | `desktop` | ROS 2 install target (`desktop` / `base`) |
| `CMAKE_VERSION` | `4.3.2` | CMake version to install |
| `USERNAME` | `luciole` | Non-root user name |

## Quick Start

### Pull from Registry

```bash
docker pull ghcr.io/dkuav/luciole-humble-l4t-runtime:latest
docker run -it --rm --runtime nvidia ghcr.io/dkuav/luciole-humble-l4t-runtime:latest bash
```

### Local Build (arm64 host required)

```bash
cd src/luciole-humble-l4t-runtime
docker compose build
```

Or from the repo root:

```bash
docker build -f src/luciole-humble-l4t-runtime/Dockerfile -t luciole-humble-l4t-runtime .
```

## ROS 2 Setup

ROS 2 is installed but **not sourced** automatically. Source it manually before use:

```bash
source /opt/ros/humble/setup.bash
```

## Notes

- This is a **Tier 2 final image** that depends on `luciole-l4t-base`.
- **arm64 only** — for amd64/CUDA use [`luciole-humble-cuda-runtime`](../luciole-humble-cuda-runtime/README.md).
- No devshell — the default shell is `bash`. The `load_ros` alias and zsh configuration are not available.
- Suitable for Jetson-based deployment, CI pipelines, or any scenario that does not need interactive dev tools.
- Requires `--runtime nvidia` (or equivalent) on the host for GPU acceleration.
