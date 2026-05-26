# luciole-l4t-base

DKUAV / Luciole 项目的 L4T（Linux for Tegra）基础镜像。构建于 NVIDIA L4T TensorRT 镜像之上，为运行在 NVIDIA Jetson 设备上的所有 L4T 家族第二层镜像提供系统工具、pip 包及预配置的非 root 用户。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-l4t-base:latest
```

## 支持架构

仅 `arm64`（NVIDIA Jetson）

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | `nvcr.io/nvidia/l4t-tensorrt:r10.3.0-devel`（已含 Python + TensorRT，arm64）|
| **系统工具** | wget、vim、git、git-lfs、curl、zip/unzip、tmux、screen、htop、tree、parallel、rsync、build-essential、ninja-build、GDB、libssl、iputils、libgflags、libgoogle-glog、GTest / GMock、libopencv |
| **Python** | 由基础镜像提供；通过阿里云镜像追加 pip 包：uv、pytest 套件、FastAPI、pybind11、OpenCV、pandas、numpy、loguru 等 |
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
docker pull ghcr.io/dkuav/luciole-l4t-base:latest
docker run -it --rm --runtime nvidia ghcr.io/dkuav/luciole-l4t-base:latest bash
```

### 本地构建（需要 arm64 宿主机）

```bash
cd src/luciole-l4t-base
docker compose build
```

或从仓库根目录构建：

```bash
docker build -f src/luciole-l4t-base/Dockerfile -t luciole-l4t-base .
```

## 注意事项

- 这是一个 L4T（Jetson）家族的**第一层基础镜像**，已发布至 GHCR，供 [`luciole-humble-l4t-dev`](../luciole-humble-l4t-dev/README_zh.md) 和 [`luciole-humble-l4t-runtime`](../luciole-humble-l4t-runtime/README_zh.md) 以 `FROM ghcr.io/dkuav/luciole-l4t-base:latest` 方式使用。
- 由于 `l4t-tensorrt:r10.3.0-devel` 已内置 Python，构建时跳过 `02-python-install.sh`。
- **仅支持 arm64** — 本镜像不构建 amd64 版本，CI 使用原生 `ubuntu-24.04-arm` Runner。
- 本镜像不含 ROS 2、cmake、clang 或 devshell，这些内容由第二层最终镜像负责添加。
- 若基础镜像中 UID/GID 已被占用，构建时会自动删除原有用户后再创建 `luciole`。
