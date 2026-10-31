# luciole-cuda-base

共享 NVIDIA PyTorch/CUDA 基础镜像，包含系统工具、GUI 依赖、Python 包、CMake、网络库与预配置用户。

> English documentation: [README.md](README.md)

## 镜像地址与平台

`ghcr.io/dkuav/luciole-cuda-base:latest` — `linux/amd64` 和 `linux/arm64`。
Main 还发布 `main`、`sha-<7位提交号>`；`v*` 事件发布版本和 SHA 标签。

## 内容

| 类别 | 说明 |
| --- | --- |
| 基础 | `nvcr.io/nvidia/pytorch:26.06-py3`，Python、PyTorch 和 CUDA 由上游提供 |
| 系统 / 构建 | vim、Git/LFS、tmux、ripgrep、fd、bat、ffmpeg、GCC、Ninja、GDB、CMake 4.3.2 |
| Python 包 | uv、pytest 工具、FastAPI、pybind11、pandas、numpy、loguru 和 OpenCV wheels；见 [pip-packages.sh](../_scripts/pip-packages.sh) |
| 网络库 | libdatachannel v0.24.5、rpclib v2.3.0、iceoryx v2.0.8 |
| GUI | WSLg 依赖、D-Bus、CJK 字体、Mesa 和 PulseAudio |
| OpenCV | apt `libopencv-dev` 与 pip 包；`opencv.sh` 未启用，当前 Dockerfile 不隔离 NVIDIA OpenCV |
| 软件源 | 上游 Ubuntu / PyPI 源；最终镜像切换至 Aliyun |
| 编辑器 / 时区 | `EDITOR=vim`、`VISUAL=vim`，默认 `Asia/Shanghai` |

## 用户与入口脚本

默认容器用户为 `root`，默认命令为 `/bin/bash`。配置的 `luciole` 账户 UID/GID 为 1000，具有免密 sudo 权限。Base 不覆盖上游工作目录。

身份由 Dockerfile 的 `USER` 决定，即使覆盖 ENTRYPOINT 也保持该身份。共享入口脚本通过 `sudo -n` 启动 sshd，然后 exec 用户命令。`APP_USER` 是描述性元数据，不控制权限；需要 root 会话时显式使用 `docker run --user root`。运行时不使用 gosu 降权。

## 构建参数

标准构建使用[清单](image.yml)中的值；直接构建仍可使用 Dockerfile 默认值。修改默认值时同步更新两者。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `BASE_IMAGE` | `nvcr.io/nvidia/pytorch:26.06-py3` | 外部基础镜像；清单 digest 可锁定内容 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `CMAKE_VERSION` | `4.3.2` | CMake 版本 |
| `LIBDATACHANNEL_VERSION` | `v0.24.5` | libdatachannel 版本 |
| `RPCLIB_VERSION` | `v2.3.0` | rpclib 版本 |
| `ICEORYX_VERSION` | `v2.0.8` | iceoryx 版本 |
| `USERNAME` | `luciole` | 配置的账户名，必须与内部基础镜像一致 |
| `USER_UID` | `1000` | 账户 UID |
| `USER_GID` | `1000` | 账户 GID；直接构建默认跟随 USER_UID |

## 快速开始

```bash
docker pull ghcr.io/dkuav/luciole-cuda-base:latest
docker run --rm -it --gpus all ghcr.io/dkuav/luciole-cuda-base:latest
```

## 清单构建与测试

按[根文档](../../README_zh.md#本地构建与烟测)安装工具，ARM64 宿主机使用原生 `linux/arm64` 平台。

```bash
# 安装工具后在仓库根目录执行。
python -m tools.images plan --image luciole-cuda-base --output build-plan.json
revision=$(git rev-parse HEAD)
python -m tools.images bake --plan build-plan.json --owner dkuav \
  --repository dkuav/images --revision "$revision" --platform linux/amd64 \
  --mode load --output docker-bake.load.json
docker buildx bake --file docker-bake.load.json
python -m tools.images test --plan build-plan.json --owner dkuav \
  --revision "$revision" --platform linux/amd64
```

Bake 流程构建当前工作区的依赖，只有显式选择的镜像标记为发布。Advisory：断言失败仅报告，不阻断发布。 Docker、构建或缺失脚本错误始终导致失败，包括 advisory 镜像。

## Compose 与直接构建

```bash
cd src/luciole-cuda-base
docker compose build
# 在仓库根目录：
docker build -f src/luciole-cuda-base/Dockerfile -t luciole-cuda-base .
```

直接通过 Docker/Compose 构建最终镜像时，默认使用已发布的 base。验证当前工作区依赖时使用 Bake。Base Compose 仅用于构建；dev/runtime Compose 配置交互终端和 SSH `2222:22` 映射。

## SSH

```bash
docker run -dit --gpus all -p 2222:22 ghcr.io/dkuav/luciole-cuda-base:latest
ssh -p 2222 luciole@localhost
```

现有配置启用 SSH 公钥认证和 root 登录。配置的 `luciole` 账户密码为 `123456`；root 密码继承上游，`user.sh` 不设置它。Host key 在构建时生成。Compose 映射宿主机 2222 端口；`docker compose run --rm --service-ports app` 会发布配置的端口。

## 已知上游问题

`opencv.sh` 当前未启用。Dev-tools 安装 apt OpenCV，但 Dockerfile 不隔离 NVIDIA 安装，也不保证 `find_package(OpenCV)` 解析到 apt。Python 包单独安装。已有烟测断言保留，可能报告差异。

历史 [OpenCV 分析](../../docs/opencv-status_zh.md)和[链接器诊断](../../docs/ld-cache-notes_zh.md)包含特定旧构建的证据。当前 base Dockerfile 没有 HPC-X 修复步骤。手动诊断工作流继续保留，本次构建迁移不解决上游兼容问题。

配置与发布细节见[构建架构](../../docs/build-architecture_zh.md)和[清单参考](../../docs/manifest-reference_zh.md)。
