# luciole-humble-l4t-dev

Full L4T development container (arm64) with ROS 2 Humble, a complete C++ / Python toolchain, and a comfortable interactive shell. Designed for day-to-day development on NVIDIA Jetson devices.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-humble-l4t-dev:latest
```

## Architecture

`arm64` only (NVIDIA Jetson)

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | [`ghcr.io/dkuav/luciole-l4t-base`](../luciole-l4t-base/README.md) (system tools, TensorRT/Python, pip packages, user) |
| **ROS 2** | Humble Base (`ros-humble-base`) + `colcon`, `rosdep`, `rosinstall-generator` |
| **Build tools** | CMake 4.3.2 (binary release, aarch64) |
| **C++ toolchain** | LLVM 21 — `clang-format`, `clang-tidy`, `lldb` |
| **Runtime** | .NET SDK 8.0 |
| **Dev shell** | zsh + oh-my-zsh + neovim + starship + nvm + bat + fzf + eza + zoxide + more |
| **Pre-commit** | pre-commit with pre-cached hook environments (ruff, trailing-whitespace, etc.) |

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
| `ROS_TARGET` | `base` | ROS 2 install target (`desktop` / `base`) |
| `CMAKE_VERSION` | `4.3.2` | CMake version to install |
| `USERNAME` | `luciole` | Non-root user name |

## Quick Start

### Pull from Registry

```bash
docker pull ghcr.io/dkuav/luciole-humble-l4t-dev:latest
docker run -it --rm --runtime nvidia ghcr.io/dkuav/luciole-humble-l4t-dev:latest
```

### Local Build (arm64 host required)

```bash
cd src/luciole-humble-l4t-dev
docker compose build
```

Or from the repo root:

```bash
docker build -f src/luciole-humble-l4t-dev/Dockerfile -t luciole-humble-l4t-dev .
```

### Start with WSLg GUI Support

```bash
cd src/luciole-humble-l4t-dev
docker compose run --rm app
```

The `docker-compose.yml` sets `platform: linux/arm64`, mounts the X11 and wslg sockets, and forwards `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and `PULSE_SERVER` so GUI applications work inside the container.

## ROS 2 Setup

ROS 2 is installed but **not sourced** automatically in the shell to avoid conflicts. Use the provided alias to source the workspace:

```bash
load_ros          # sources /opt/ros/humble/setup.zsh
```

You can add `load_ros` to your `~/.zshrc` if you want it sourced on every shell start.

## Notes

- This is a **Tier 2 final image** that depends on `luciole-l4t-base`.
- **arm64 only** — for amd64/CUDA use [`luciole-humble-cuda-dev`](../luciole-humble-cuda-dev/README.md).
- neovim (aarch64 binary), nvm, and oh-my-zsh are installed into the `luciole` user's home directory by `devshell.sh`.
- The default working directory in the container is `/home/luciole`.
- Requires `--runtime nvidia` (or equivalent) on the host for GPU acceleration.
