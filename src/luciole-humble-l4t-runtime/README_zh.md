# luciole-humble-l4t-runtime

包含 ROS 2 Humble 和 CMake 的轻量级 L4T 运行时容器（arm64）。不含交互式开发工具、devshell 或 C++ 工具链扩展。专为 NVIDIA Jetson 部署及 CI 流水线而设计。

> For English documentation, see [README.md](README.md)

## Registry

```
ghcr.io/dkuav/luciole-humble-l4t-runtime:latest
```

## 支持架构

仅 `arm64`（NVIDIA Jetson）

## 内置内容

| 类别 | 详情 |
|------|------|
| **基础镜像** | [`ghcr.io/dkuav/luciole-l4t-base`](../luciole-l4t-base/README_zh.md)（系统工具、TensorRT/Python、pip 包、用户）|
| **ROS 2** | Humble Base（`ros-humble-base`）+ `colcon`、`rosdep`、`rosinstall-generator` |
| **构建工具** | CMake 4.3.2（aarch64 二进制发行版）|

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
| `ROS_TARGET` | `base` | ROS 2 安装目标（`desktop` / `base`）|
| `CMAKE_VERSION` | `4.3.2` | 安装的 CMake 版本 |
| `USERNAME` | `luciole` | 非 root 用户名 |

## 快速开始

### 从 Registry 拉取

```bash
docker pull ghcr.io/dkuav/luciole-humble-l4t-runtime:latest
docker run -it --rm --runtime nvidia ghcr.io/dkuav/luciole-humble-l4t-runtime:latest bash
```

### 本地构建（需要 arm64 宿主机）

```bash
cd src/luciole-humble-l4t-runtime
docker compose build
```

或从仓库根目录构建：

```bash
docker build -f src/luciole-humble-l4t-runtime/Dockerfile -t luciole-humble-l4t-runtime .
```

## ROS 2 配置

ROS 2 已安装但**不会**自动加载到 Shell。使用前请手动加载：

```bash
source /opt/ros/humble/setup.bash
```

## 注意事项

- 这是依赖 `luciole-l4t-base` 的**第二层最终镜像**。
- **仅支持 arm64** — amd64 / CUDA 环境请使用 [`luciole-humble-cuda-runtime`](../luciole-humble-cuda-runtime/README_zh.md)。
- 不含 devshell，默认 Shell 为 `bash`，`load_ros` 别名和 zsh 配置不可用。
- 适用于基于 Jetson 的部署、CI 流水线或其他无需交互式开发工具的场景。
- 宿主机需配置 `--runtime nvidia`（或等效设置）以启用 GPU 加速。
