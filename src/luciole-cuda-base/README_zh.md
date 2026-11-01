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
| Python 包 | 共用[开发依赖清单](../../vendor/image-kit/assets/python-dev-requirements.txt)，包括 uv、ty 和 Ruff；CUDA 专属 OpenCV 与视觉包由 [luciole-cuda-pip-packages.sh](../_scripts/python/luciole-cuda-pip-packages.sh) 安装。CUDA 保留 `numpy<2.0.0`。 |
| 网络库 | libdatachannel v0.24.5、rpclib v2.3.0、iceoryx v2.0.8 |
| GUI | WSLg 依赖、D-Bus、CJK 字体、Mesa 和 PulseAudio |
| OpenCV | apt `libopencv-dev` 与 pip 包；`opencv.sh` 未启用，当前 Dockerfile 不隔离 NVIDIA OpenCV |
| 软件源 | 上游 Ubuntu / PyPI 源；最终镜像切换至 Aliyun |
| 编辑器 / 时区 | `EDITOR=vim`、`VISUAL=vim`，默认 `Asia/Shanghai` |

## 用户与入口脚本

默认容器用户为 `root`，默认命令为 `/bin/bash`。配置的 `luciole` 账户 UID/GID 为 1000，具有免密 sudo 权限。Base 不覆盖上游工作目录。

身份由 Dockerfile 的 `USER` 决定，即使覆盖 ENTRYPOINT 也保持该身份。共享入口脚本按 `SSH_MODE` 启动 sshd，再执行用户命令。默认是 password 模式，但 `luciole` 初始锁定且镜像内没有密码；默认 `DEFAULT_USER=luciole` 时禁止 root SSH 登录。`APP_USER` 仅是描述性元数据。需要 root 会话时显式使用 `docker run --user root`。

## 构建参数

标准构建使用[清单](image.yml)中的值；直接构建仍可使用 Dockerfile 默认值。修改默认值时同步更新两者。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `BASE_IMAGE` | `nvcr.io/nvidia/pytorch:26.06-py3` | 外部基础镜像；清单 digest 可锁定内容 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `SYSTEM_UPGRADE` | `true` | 系统初始化时升级已安装软件包 |
| `CMAKE_VERSION` | `4.3.2` | CMake 版本 |
| `LIBDATACHANNEL_VERSION` | `v0.24.5` | libdatachannel 版本 |
| `RPCLIB_VERSION` | `v2.3.0` | rpclib 版本 |
| `ICEORYX_VERSION` | `v2.0.8` | iceoryx 版本 |
| `USERNAME` | `luciole` | 配置的账户名，必须与内部基础镜像一致 |
| `USER_UID` | `1000` | 账户 UID |
| `USER_GID` | `1000` | 账户 GID；直接构建默认跟随 USER_UID |
| `USER_GROUPS` | 空 | 逗号分隔的已有附加用户组；root 必须为空 |

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
docker run -dit --gpus all -p 2222:22 -e SSH_PASSWORD_FILE=/run/secrets/ssh-password \
  -v "$HOME/.config/luciole/ssh-password:/run/secrets/ssh-password:ro" ghcr.io/dkuav/luciole-cuda-base:latest
ssh -p 2222 luciole@localhost
```

运行上述示例前，请在宿主机创建非空的 `$HOME/.config/luciole/ssh-password` 密码文件并限制其读取权限。默认 `SSH_MODE=password` 会启动 sshd，但 `luciole` 初始锁定。密码登录需挂载非空密码文件并设置 `SSH_PASSWORD_FILE`；公钥登录需挂载非空的 `/home/luciole/.ssh/authorized_keys` 并设置 `SSH_MODE=key-only`。不使用 SSH 时设为 `disabled`。默认 `DEFAULT_USER=luciole` 时禁止 root SSH 登录；host key 在容器启动时确保存在。仅向可信接口映射 22 端口。Compose 映射宿主机 2222 端口，但不提供凭据。

SSH 使用显式选择的 `DEFAULT_USER`：选择 `root` 后，公钥模式默认要求非空的 `/root/.ssh/authorized_keys`；root 密码登录必须挂载非空的 `SSH_PASSWORD_FILE`。root SSH 具有完整容器权限。运行时修改 `DEFAULT_USER` 只选择 SSH 账户，不改变 Dockerfile 命令用户。

## 已知上游问题

`opencv.sh` 当前未启用。Dev-tools 安装 apt OpenCV，但 Dockerfile 不隔离 NVIDIA 安装，也不保证 `find_package(OpenCV)` 解析到 apt。Python 包单独安装。已有烟测断言保留，可能报告差异。

历史 [OpenCV 分析](../../docs/opencv-status_zh.md)和[链接器诊断](../../docs/ld-cache-notes_zh.md)包含特定旧构建的证据。当前 base Dockerfile 没有 HPC-X 修复步骤。手动诊断工作流继续保留，本次构建迁移不解决上游兼容问题。

配置与发布细节见[构建架构](../../docs/build-architecture_zh.md)和[清单参考](../../docs/manifest-reference_zh.md)。

共享系统安装脚本仍支持 `--timezone` 和 `--upgrade`，并由 Dockerfile 显式传参。libdatachannel、rpclib 和 iceoryx 安装脚本由 Dockerfile 显式传入 `--version`，不再读取版本环境变量。`user.sh --groups` 接收清单的 `USER_GROUPS`。引用的组必须已经存在；空值不添加附加组，格式错误的列表和 root 的非空附加组会被拒绝。Dev/runtime 继承 base 配置的附加组。

共享脚本和资产来自固定提交的 `vendor/image-kit` submodule；Luciole 扩展保留在 `src/_scripts/` 和 `src/_assets/`。清单声明每个复制输入，构建前先执行 `git submodule update --init --recursive`。

共享入口命令安装为 `/usr/local/bin/docker-entrypoint`。公钥模式默认要求非空 `authorized_keys`；显式设置 `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` 时，允许 sshd 先启动，等待后续配置公钥；空文件不允许无密钥登录。

公共工具中的 `gosu` 和 `sudo` 由 image-kit 安装，`landscape-common` 由本地 `luciole-dev-tools.sh` 补充；CUDA dev/runtime 从 base 继承。

`SYSTEM_UPGRADE` 默认为 `true`，由清单与 Dockerfile 显式传给组件 `system.sh --upgrade`。本地 CUDA pip 包装脚本先升级 pip，再由组件无条件重新安装 pip 管理的 psutil，并统一解析公共开发依赖及 Luciole 视觉扩展。
