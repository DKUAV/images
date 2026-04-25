# luciole-humble-dev

Ubuntu 22.04 development container for the DKUAV / Luciole project, pre-configured with ROS 2 Humble, a rich C++/Python toolchain, and a comfortable shell environment.

> 中文文档请见 [README_zh.md](README_zh.md)

## Registry

```
ghcr.io/dkuav/luciole-humble-dev:latest
```

## What's Inside

| Category | Details |
|----------|---------|
| **Base** | `mcr.microsoft.com/devcontainers/base:ubuntu22.04` |
| **ROS 2** | Humble Desktop (`ros-humble-desktop`) + `ros-dev-tools` |
| **C++ toolchain** | GCC / G++, CMake, Ninja, GDB, clang-format 21, libgflags, libgoogle-glog, GTest / GMock |
| **Python** | Python 3.10, pip (Aliyun mirror), uv, pytest suite, FastAPI, pybind11, OpenCV, pandas, numpy, and more |
| **Shell** | zsh (default) + oh-my-zsh (`ys` theme) with zsh-completions, zsh-autosuggestions, zsh-syntax-highlighting |
| **Editors** | neovim (latest, NvChad starter config) + vim (amix awesome vimrc) |
| **Tools** | git, git-lfs, tmux, fzf, bat, tree, htop, parallel, rsync, trash-cli |
| **GUI** | WSLg support (X11 + Wayland socket mounts, CJK fonts, Mesa, PulseAudio) |
| **Mirrors** | Aliyun apt mirror + Aliyun PyPI mirror (for mainland China) |
| **Timezone** | `Asia/Shanghai` (overridable) |

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
| `TZ` | `Asia/Shanghai` | Timezone |
| `ROS_DISTRO` | `humble` | ROS 2 distribution |
| `ROS_TARGET` | `desktop` | ROS 2 metapackage (`desktop` / `base` / `desktop-full`) |
| `USERNAME` | `luciole` | Non-root user name |
| `USER_UID` | `1000` | User UID |
| `USER_GID` | `1000` | User GID |

## Quick Start

### Pull from Registry

```bash
docker pull ghcr.io/dkuav/luciole-humble-dev:latest
docker run -it --rm ghcr.io/dkuav/luciole-humble-dev:latest
```

### Local Build

```bash
cd src/luciole-humble-dev
docker compose build
docker compose run --rm app
```

Or build directly with custom ARGs:

```bash
docker build \
  --build-arg USERNAME=myuser \
  --build-arg USER_UID=$(id -u) \
  --build-arg USER_GID=$(id -g) \
  -t luciole-humble-dev .
```

### WSLg GUI

The `docker-compose.yml` automatically mounts the WSLg sockets. Start the container via Compose and GUI apps (e.g., RViz) will work out of the box on WSL2.

## ROS 2 Setup

ROS is **not** sourced by default. Use the provided aliases:

```bash
# in zsh
load_ros    # sources /opt/ros/humble/setup.zsh

# in bash
load_ros    # sources /opt/ros/humble/setup.bash
```

## Notes

- neovim is currently installed from `nvim-linux-x86_64.tar.gz` — **not compatible with arm64**. A separate arm64 image should use the `nvim-linux-aarch64.tar.gz` binary or a build ARG to select the correct archive.
- If the requested UID/GID (`1000`) is already occupied in the base image, the old user is removed automatically before creating `luciole`.
