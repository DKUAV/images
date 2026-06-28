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
| **ROS 2** | Humble `ros-base` (`ros-humble-ros-base`) + `colcon`, `rosdep`, `rosinstall-generator` |
| **SSH** | `openssh-server` (inherited from base) launched at boot by the shared entrypoint |
| **Mirrors** | As the final build step, apt + pip sources are flipped to Aliyun so Chinese users get fast installs after pulling. The build itself uses the default sources. |

> **Not included**: clang/LLVM, devshell (zsh, neovim, oh-my-zsh, etc.)

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
| `ROS_TARGET` | `ros-base` | ROS 2 install target (`desktop` / `ros-base`) |
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

## Entrypoint, SSH & APP_USER

This image inherits the shared entrypoint from
[`luciole-cuda-base`](../luciole-cuda-base/README.md#entrypoint--ssh).
On boot it starts sshd and then drops to `APP_USER=luciole`. Override
`APP_USER` (e.g. `-e APP_USER=root`) to stay root.

| Setting | Value |
|---------|-------|
| Default user on boot | `luciole` (bash) |
| SSH port (in image) | `22` (`docker-compose.yml` maps it to host `2222`) |
| Password (root / luciole) | `123456` |```

## Notes

- This is a **Tier 2 final image** that depends on `luciole-cuda-base`.
- Supports both `amd64` (x86_64 workstations) and `arm64` (NVIDIA Jetson).
- No devshell — the default shell is `bash`. The `load_ros` alias and zsh configuration are not available.
- Suitable for CI pipelines, batch inference, or any deployment scenario that does not need interactive dev tools.
