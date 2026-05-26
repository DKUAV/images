# luciole-humble-cuda-runtime

包含 ROS 2 Humble 和 CMake 的轻量级 CUDA/PyTorch 运行时容器。不含交互式开发工具、devshell 或 C++ 工具链扩展。适用于具有 NVIDIA GPU 的 amd64 机器上的部署及 CI 流水线。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-humble-cuda-runtime:latest
```

## 支持架构

仅 `amd64`

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | [`ghcr.io/dkuav/luciole-cuda-base`](../luciole-cuda-base/README_zh.md)（系统工具、PyTorch/CUDA、pip 包、用户）|
| **ROS 2** | Humble Desktop（`ros-humble-desktop`）+ `colcon`、`rosdep`、`rosinstall-generator` |
| **构建工具** | CMake 4.3.2（二进制发行版）|

> **不包含**：clang/LLVM、.NET SDK、devshell（zsh、neovim、oh-my-zsh 等）

## 默认用户

| 配置项 | 值 |
|--------|----|
| 用户名 | `luciole` |
| UID / GID | `1000` / `1000` |
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
docker pull ghcr.io/dkuav/luciole-humble-cuda-runtime:latest
docker run -it --rm --gpus all ghcr.io/dkuav/luciole-humble-cuda-runtime:latest bash
```

### 本地构建

```bash
cd src/luciole-humble-cuda-runtime
docker compose build
```

或从仓库根目录构建：

```bash
docker build -f src/luciole-humble-cuda-runtime/Dockerfile -t luciole-humble-cuda-runtime .
```

## ROS 2 配置

ROS 2 已安装但**不会**自动加载到 Shell。使用前请手动加载：

```bash
source /opt/ros/humble/setup.bash
```

## 注意事项

- 这是依赖 `luciole-cuda-base` 的**第二层最终镜像**。
- 仅支持 amd64 — Jetson / arm64 环境请使用 [`luciole-humble-l4t-runtime`](../luciole-humble-l4t-runtime/README_zh.md)。
- 不含 devshell，默认 Shell 为 `bash`，`load_ros` 别名和 zsh 配置不可用。
- 适用于 CI 流水线、批量推理或其他无需交互式开发工具的部署场景。
