# luciole-humble-l4t-dev

包含 ROS 2 Humble、完整 C++ / Python 工具链及舒适交互式 Shell 的全功能 L4T 开发容器（arm64）。专为在 NVIDIA Jetson 设备上进行日常开发而设计。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-humble-l4t-dev:latest
```

## 支持架构

仅 `arm64`（NVIDIA Jetson）

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | [`ghcr.io/dkuav/luciole-l4t-base`](../luciole-l4t-base/README_zh.md)（系统工具、TensorRT/Python、pip 包、用户）|
| **ROS 2** | Humble Desktop（`ros-humble-desktop`）+ `colcon`、`rosdep`、`rosinstall-generator` |
| **构建工具** | CMake 4.3.2（aarch64 二进制发行版）|
| **C++ 工具链** | LLVM 21 — `clang-format`、`clang-tidy`、`lldb` |
| **运行时** | .NET SDK 8.0 |
| **开发 Shell** | zsh + oh-my-zsh + neovim + starship + nvm + bat + fzf + eza + zoxide 等 |

## 默认用户

| 配置项 | 值 |
|--------|----|
| 用户名 | `luciole` |
| UID / GID | `1000` / `1000` |
| Shell | `/bin/zsh` |
| sudo | 免密码 |

## 构建参数（ARG）

| ARG | 默认值 | 说明 |
|-----|--------|------|
| `ROS_DISTRO` | `humble` | ROS 2 发行版 |
| `ROS_TARGET` | `desktop` | ROS 2 安装目标（`desktop` / `base`）|
| `CMAKE_VERSION` | `4.3.2` | 安装的 CMake 版本 |
| `USERNAME` | `luciole` | 非 root 用户名 |

## 快速开始

### 从 Registry 拉取

```bash
docker pull ghcr.io/dkuav/luciole-humble-l4t-dev:latest
docker run -it --rm --runtime nvidia ghcr.io/dkuav/luciole-humble-l4t-dev:latest
```

### 本地构建（需要 arm64 宿主机）

```bash
cd src/luciole-humble-l4t-dev
docker compose build
```

或从仓库根目录构建：

```bash
docker build -f src/luciole-humble-l4t-dev/Dockerfile -t luciole-humble-l4t-dev .
```

### 启动并支持 WSLg GUI

```bash
cd src/luciole-humble-l4t-dev
docker compose run --rm luciole-humble-l4t-dev
```

`docker-compose.yml` 设置了 `platform: linux/arm64`，挂载 X11 和 wslg socket，并转发 `DISPLAY`、`WAYLAND_DISPLAY`、`XDG_RUNTIME_DIR`、`PULSE_SERVER` 等环境变量，使容器内的 GUI 程序可正常运行。

## ROS 2 配置

ROS 2 已安装但**不会**自动加载到 Shell，以避免潜在冲突。可使用内置别名手动加载：

```bash
load_ros          # 执行 source /opt/ros/humble/setup.zsh
```

如需每次打开 Shell 时自动加载，可将 `load_ros` 添加到 `~/.zshrc`。

## 注意事项

- 这是依赖 `luciole-l4t-base` 的**第二层最终镜像**。
- **仅支持 arm64** — amd64 / CUDA 环境请使用 [`luciole-humble-cuda-dev`](../luciole-humble-cuda-dev/README_zh.md)。
- neovim（aarch64 二进制）、nvm 和 oh-my-zsh 由 `09-devshell.sh` 安装到 `luciole` 用户的 home 目录下。
- 容器内默认工作目录为 `/home/luciole`。
- 宿主机需配置 `--runtime nvidia`（或等效设置）以启用 GPU 加速。
