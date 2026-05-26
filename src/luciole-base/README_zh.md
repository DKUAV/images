# luciole-base

DKUAV / Luciole 项目的 Ubuntu 22.04 基础镜像。为所有 Ubuntu 家族的第二层镜像提供基础层——系统工具、Python 3.10、pip 包以及预配置的非 root 用户。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-base:latest
```

## 支持架构

`amd64` + `arm64`

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | `mcr.microsoft.com/devcontainers/base:ubuntu22.04` |
| **系统工具** | wget、vim、git、git-lfs、curl、zip/unzip、tmux、screen、htop、tree、parallel、rsync、build-essential、ninja-build、GDB、libssl、iputils、libgflags、libgoogle-glog、GTest / GMock、libopencv |
| **Python** | Python 3.10、pip（阿里云镜像）、uv、pytest 套件、FastAPI、pybind11、OpenCV、pandas、numpy、loguru 等 |
| **GUI** | WSLg 支持（dbus-x11、中日韩字体、Mesa、PulseAudio）|
| **镜像加速** | 阿里云 apt 镜像 + 阿里云 PyPI 镜像 |
| **时区** | `Asia/Shanghai`（可通过 `TZ` 覆盖）|

## 默认用户

| 配置项 | 值 |
|--------|----|
| 用户名 | `luciole` |
| UID / GID | `1000` / `1000` |
| sudo | 免密码 |

## 构建参数（ARG）

| ARG | 默认值 | 说明 |
|-----|--------|------|
| `TZ` | `Asia/Shanghai` | 时区 |
| `USERNAME` | `luciole` | 非 root 用户名 |
| `USER_UID` | `1000` | 用户 UID |
| `USER_GID` | `1000` | 用户 GID |

## 快速开始

```bash
docker pull ghcr.io/dkuav/luciole-base:latest
docker run -it --rm ghcr.io/dkuav/luciole-base:latest bash
```

### 本地构建

```bash
cd src/luciole-base
docker compose build
```

或从仓库根目录构建：

```bash
docker build -f src/luciole-base/Dockerfile -t luciole-base .
```

## 注意事项

- 这是一个**第一层基础镜像**，已发布至 GHCR，供 [`luciole-humble-dev`](../luciole-humble-dev/README_zh.md) 等第二层镜像以 `FROM ghcr.io/dkuav/luciole-base:latest` 方式使用。
- 本镜像不含 ROS 2、cmake、clang 或 devshell，这些内容由第二层最终镜像负责添加。
- 若基础镜像中 UID/GID 已被占用，构建时会自动删除原有用户后再创建 `luciole`。
