# luciole-cuda-dev

Full CUDA/PyTorch development container with ROS 2 Humble, a complete C++ / Python toolchain, and a comfortable interactive shell. Designed for day-to-day development on amd64 workstations and arm64 (Jetson) boards with NVIDIA GPU support.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-cuda-dev:latest
```

## Architecture

`amd64` + `arm64`

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | [`ghcr.io/dkuav/luciole-cuda-base`](../luciole-cuda-base/README.md) (system tools, PyTorch/CUDA, pip packages, CMake, user) |
| **ROS 2** | Humble `ros-base` (`ros-humble-ros-base`) + `colcon`, `rosdep`, `rosinstall-generator` |
| **C++ toolchain** | LLVM 21 — `clang-format`, `clang-tidy`, `lldb` |
| **Dev shell** | zsh + oh-my-zsh + neovim + starship + nvm + bat + fzf + eza + zoxide + more |
| **Pre-commit** | pre-commit with pre-cached hook environments (ruff, trailing-whitespace, etc.) |
| **Mirrors** | As the final build step, apt + pip sources are flipped to Aliyun so Chinese users get fast installs after pulling. The build itself uses the default sources. |

## Default User

| Setting | Value |
|---------|-------|
| Username | `luciole` |
| UID / GID | `1000` / `1000` |
| Shell | `/bin/zsh` |
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
docker pull ghcr.io/dkuav/luciole-cuda-dev:latest
docker run -it --rm --gpus all ghcr.io/dkuav/luciole-cuda-dev:latest
```

### Local Build

```bash
cd src/luciole-cuda-dev
docker compose build
```

Or from the repo root:

```bash
docker build -f src/luciole-cuda-dev/Dockerfile -t luciole-cuda-dev .
```

### Start with WSLg GUI Support

```bash
cd src/luciole-cuda-dev
docker compose run --rm app
```

The `docker-compose.yml` mounts `/tmp/.X11-unix` and `/mnt/wslg`, and forwards `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and `PULSE_SERVER` so GUI applications work inside the container under WSLg.

## ROS 2 Setup

ROS 2 is installed but **not sourced** automatically in the shell to avoid conflicts. Use the provided alias to source the workspace:

```bash
load_ros          # sources /opt/ros/humble/setup.zsh
```

You can add `load_ros` to your `~/.zshrc` if you want it sourced on every shell start.

## Notes

- This is a **Tier 2 final image** that depends on `luciole-cuda-base`.
- Supports both `amd64` (x86_64 workstations) and `arm64` (NVIDIA Jetson).
- neovim, nvm, and oh-my-zsh are installed into the `luciole` user's home directory by `devshell.sh`.
- The default working directory in the container is `/home/luciole`.
