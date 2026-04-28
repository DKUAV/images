# luciole-humble-dev

DKUAV / Luciole 项目的 Ubuntu 22.04 开发容器，预装 ROS 2 Humble、完整 C++/Python 工具链及舒适的 Shell 环境。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-humble-dev:latest
```

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | `mcr.microsoft.com/devcontainers/base:ubuntu22.04` |
| **ROS 2** | Humble Desktop（`ros-humble-desktop`）+ `ros-dev-tools` |
| **C++ 工具链** | GCC / G++、CMake、Ninja、GDB、clang-format 21、libgflags、libgoogle-glog、GTest / GMock |
| **Python** | Python 3.10、pip（阿里云镜像）、uv、pytest 套件、FastAPI、pybind11、OpenCV、pandas、numpy 等 |
| **Shell** | zsh（默认）+ oh-my-zsh（`ys` 主题）+ zsh-completions、zsh-autosuggestions、zsh-syntax-highlighting |
| **编辑器** | neovim（最新版，NvChad starter 配置）+ vim（amix awesome vimrc）|
| **工具** | git、git-lfs、tmux、fzf、bat、tree、htop、parallel、rsync、trash-cli |
| **GUI** | WSLg 支持（X11 + Wayland socket 挂载、中日韩字体、Mesa、PulseAudio）|
| **镜像加速** | 阿里云 apt 镜像 + 阿里云 PyPI 镜像（适用于中国大陆网络环境）|
| **时区** | `Asia/Shanghai`（可通过 ARG 覆盖）|

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
| `TZ` | `Asia/Shanghai` | 时区 |
| `ROS_DISTRO` | `humble` | ROS 2 发行版 |
| `ROS_TARGET` | `desktop` | ROS 2 元包（`desktop` / `base` / `desktop-full`）|
| `USERNAME` | `luciole` | 非 root 用户名 |
| `USER_UID` | `1000` | 用户 UID |
| `USER_GID` | `1000` | 用户 GID |

## 快速开始

### 从 Registry 拉取

直接使用 `docker` 命令：

```bash
docker pull ghcr.io/dkuav/luciole-humble-dev:latest
docker run -it --rm ghcr.io/dkuav/luciole-humble-dev:latest
```

或使用 `docker compose`（推荐，WSLg 挂载已预配置）：

```bash
cd src/luciole-humble-dev
docker compose run --rm app
```

`docker-compose.yml` 已指向 `ghcr.io/dkuav/luciole-humble-dev:latest`，本地不存在镜像时 Docker 会自动拉取。

### 本地构建

```bash
cd src/luciole-humble-dev
docker compose build
docker compose run --rm app
```

或直接使用自定义 ARG 构建：

```bash
docker build \
  --build-arg USERNAME=myuser \
  --build-arg USER_UID=$(id -u) \
  --build-arg USER_GID=$(id -g) \
  -t luciole-humble-dev .
```

### WSLg GUI 支持

`docker-compose.yml` 已自动挂载 WSLg socket。通过 Compose 启动容器后，GUI 应用（如 RViz）在 WSL2 环境下即可直接运行。

## ROS 2 环境配置

ROS 环境**默认不自动 source**，可使用内置别名手动加载：

```bash
# zsh 中
load_ros    # 执行 source /opt/ros/humble/setup.zsh

# bash 中
load_ros    # 执行 source /opt/ros/humble/setup.bash
```

## 注意事项

- neovim 通过检测构建宿主架构（`uname -m`）自动选择安装包：`x86_64` 使用 `nvim-linux-x86_64.tar.gz`，`aarch64` 使用 `nvim-linux-arm64.tar.gz`，已同时支持 amd64 与 arm64。
- 若基础镜像中 UID/GID `1000` 已被占用，构建时会自动删除原有用户后再创建 `luciole`。
