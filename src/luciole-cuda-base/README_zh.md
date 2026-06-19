# luciole-cuda-base

DKUAV / Luciole 项目的 CUDA/PyTorch 基础镜像。构建于 NVIDIA 官方 PyTorch 镜像之上，为所有 CUDA 家族的第二层镜像提供系统工具、pip 包及预配置的非 root 用户。同时面向 amd64（x86_64 工作站）与 arm64（NVIDIA Jetson）两种架构。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-cuda-base:latest
```

## 支持架构

`amd64` + `arm64`

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | `nvcr.io/nvidia/pytorch:24.10-py3`（已含 Python + PyTorch + CUDA）|
| **系统工具** | wget、vim、git、git-lfs、curl、zip/unzip、tmux、screen、htop、tree、parallel、rsync、build-essential、ninja-build、GDB、libssl、iputils、libgflags、libgoogle-glog、GTest / GMock |
| **Python** | 由基础镜像提供；构建期间追加 pip 包（uv、pytest 套件、FastAPI、pybind11、pandas、numpy、loguru 等）|
| **OpenCV** | C++：apt `libopencv-dev` 4.5.4（启用 FFMPEG + GStreamer）。Python：pip `opencv-contrib-python`（自带静态 FFMPEG）。NVIDIA 基础镜像自带的 OpenCV 4.7.0 库被移至 `/usr/local/lib/nvidia-opencv-4.7.0.disabled/`，确保 C++ `find_package(OpenCV)` 解析到 apt 版。详见 [`docs/opencv-status_zh.md`](../../docs/opencv-status_zh.md) |
| **构建工具** | CMake 4.3.2（二进制发行版）|
| **GUI** | WSLg 支持（dbus-x11、中日韩字体、Mesa、PulseAudio）|
| **镜像加速** | 本 **基础镜像** 保持默认 Ubuntu / PyPI 源（构建期一并使用）。下游第二层最终镜像（`luciole-cuda-dev`、`luciole-cuda-runtime`）会在其构建的最后一步将持久化的源切换到阿里云。 |
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
| `CMAKE_VERSION` | `4.3.2` | 安装的 CMake 版本 |
| `USERNAME` | `luciole` | 非 root 用户名 |
| `USER_UID` | `1000` | 用户 UID |
| `USER_GID` | `1000` | 用户 GID |

## 快速开始

```bash
docker pull ghcr.io/dkuav/luciole-cuda-base:latest
docker run -it --rm --gpus all ghcr.io/dkuav/luciole-cuda-base:latest bash
```

### 本地构建

```bash
cd src/luciole-cuda-base
docker compose build
```

或从仓库根目录构建：

```bash
docker build -f src/luciole-cuda-base/Dockerfile -t luciole-cuda-base .
```

## 注意事项

- 这是一个**第一层基础镜像**，已发布至 GHCR，供 [`luciole-cuda-dev`](../luciole-cuda-dev/README_zh.md) 和 [`luciole-cuda-runtime`](../luciole-cuda-runtime/README_zh.md) 以 `FROM ghcr.io/dkuav/luciole-cuda-base:latest` 方式使用。
- 由于 `pytorch:24.10-py3` 已内置 Python，构建时跳过 `python-install.sh`。
- 本镜像预装 CMake，使两个第二层镜像共享同一个构建工具版本。
- 本镜像不含 ROS 2、clang 或 devshell，这些内容由第二层最终镜像负责添加。
- **OpenCV 替换**：NVIDIA `pytorch:24.10-py3` 自带的 `/usr/local/lib/libopencv_*.so.4.7.0` 在构建时禁用了全部视频解码后端（FFMPEG、GStreamer）。`opencv.sh` 把它隔离到 `/usr/local/lib/nvidia-opencv-4.7.0.disabled/`，并安装 apt 的 `libopencv-dev` 4.5.4（含全部后端）用于 C++ `find_package(OpenCV)`。Python `import cv2` 继续使用 pip 的 `opencv-contrib-python` wheel，该 wheel 自带静态 FFMPEG，与 C++ OpenCV 互不干扰。完整分析见 [`docs/opencv-status_zh.md`](../../docs/opencv-status_zh.md)。
- 若基础镜像中 UID/GID 已被占用，构建时会自动删除原有用户后再创建 `luciole`。
