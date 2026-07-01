# luciole-cuda-dev

包含 ROS 2 Jazzy、完整 C++ / Python 工具链及舒适交互式 Shell 的全功能 CUDA/PyTorch 开发容器。专为具有 NVIDIA GPU 的 amd64 工作站和 arm64（Jetson）板卡日常开发而设计。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-cuda-dev:latest
```

## 支持架构

`amd64` + `arm64`

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | [`ghcr.io/dkuav/luciole-cuda-base`](../luciole-cuda-base/README_zh.md)（系统工具、PyTorch/CUDA、pip 包、CMake、用户）|
| **ROS 2** | Jazzy `ros-base`（`ros-jazzy-ros-base`）+ `colcon`、`rosdep`、`rosinstall-generator` |
| **C++ 工具链** | LLVM 21 — `clang-format`、`clang-tidy`、`lldb` |
| **开发 Shell** | zsh + oh-my-zsh + neovim + starship + nvm + bat + fzf + eza + zoxide 等 |
| **Pre-commit** | pre-commit 及预缓存 hook 环境（ruff、trailing-whitespace 等）|
| **SSH** | 继承自 base 的 `openssh-server`，由共享 entrypoint 在启动时拉起；连接映射的端口即可 |
| **镜像加速** | 构建最后一步会将 apt 与 pip 源切换为阿里云，用户 pull 后在国内可快速 apt/pip 安装；构建期仍使用默认源。 |

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
| `ROS_DISTRO` | `jazzy` | ROS 2 发行版 |
| `ROS_TARGET` | `ros-base` | ROS 2 安装目标（`desktop` / `ros-base`）|
| `USERNAME` | `luciole` | 非 root 用户名 |

## 快速开始

### 从 Registry 拉取

```bash
docker pull ghcr.io/dkuav/luciole-cuda-dev:latest
docker run -it --rm --gpus all ghcr.io/dkuav/luciole-cuda-dev:latest
```

### 本地构建

```bash
cd src/luciole-cuda-dev
docker compose build
```

或从仓库根目录构建：

```bash
docker build -f src/luciole-cuda-dev/Dockerfile -t luciole-cuda-dev .
```

### 启动并支持 WSLg GUI

```bash
cd src/luciole-cuda-dev
docker compose run --rm app
```

`docker-compose.yml` 会挂载 `/tmp/.X11-unix` 和 `/mnt/wslg`，并转发 `DISPLAY`、`WAYLAND_DISPLAY`、`XDG_RUNTIME_DIR`、`PULSE_SERVER` 等环境变量，使容器内的 GUI 程序可在 WSLg 下正常运行。

## ROS 2 配置

ROS 2 已安装但**不会**自动加载到 Shell，以避免潜在冲突。可使用内置别名手动加载：

```bash
load_ros          # 执行 source /opt/ros/jazzy/setup.zsh
```

如需每次打开 Shell 时自动加载，可将 `load_ros` 添加到 `~/.zshrc`。

## Entrypoint、SSH 与 APP_USER

本镜像继承自
[`luciole-cuda-base`](../luciole-cuda-base/README_zh.md#entrypoint-与-ssh) 的
共享 entrypoint。启动时会拉起 sshd，随后降权到 `APP_USER=luciole`，因此
一条 `docker run -it` 会直接进入 `luciole` 用户的 zsh。可用
`APP_USER`（例如 `-e APP_USER=root`）覆盖以保持 root。

| 配置项 | 值 |
|--------|----|
| 启动后默认用户 | `luciole`（zsh）|
| SSH 端口（镜像内）| `22`（`docker-compose.yml` 映射到宿主机 `2222`）|
| 口令（root / luciole）| `123456` |

通过 SSH 快速验证：

```bash
docker run -d --gpus all -p 2222:22 ghcr.io/dkuav/luciole-cuda-dev:latest
ssh -p 2222 luciole@localhost
```

## 注意事项

- 这是依赖 `luciole-cuda-base` 的**第二层最终镜像**。
- 同时支持 `amd64`（x86_64 工作站）和 `arm64`（NVIDIA Jetson）。
- neovim、nvm 和 oh-my-zsh 由 `devshell.sh` 安装到 `luciole` 用户的 home 目录下。
- 容器内默认工作目录为 `/home/luciole`。
