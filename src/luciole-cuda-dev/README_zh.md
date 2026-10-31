# luciole-cuda-dev

在 base 上增加 ROS 2 Jazzy、LLVM 21、交互式开发 shell 与预缓存 pre-commit 环境的开发镜像。

> English documentation: [README.md](README.md)

## 镜像地址与平台

`ghcr.io/dkuav/luciole-cuda-dev:latest` — `linux/amd64` 和 `linux/arm64`。
Main 还发布 `main`、`sha-<7位提交号>`；`v*` 事件发布版本和 SHA 标签。

## 内容

| 类别 | 说明 |
| --- | --- |
| 基础 | [luciole-cuda-base](../luciole-cuda-base/README_zh.md)：PyTorch/CUDA、工具、pip 包、CMake、网络库与用户 |
| ROS 2 | Jazzy `ros-base`、colcon、rosdep 和 rosinstall-generator |
| 软件源 | 所有软件安装完成后切换至 Aliyun apt/pip 源；构建过程使用上游源 |
| SSH / GUI | 从 base 继承 SSH 服务端和 WSLg 依赖 |
| LLVM | LLVM 21：clang-format、clang-tidy 和 lldb |
| 开发 shell | zsh、oh-my-zsh、NvChad/neovim、starship、nvm、fzf、eza、zoxide 等 |
| Pre-commit | 按共享配置预缓存 hook 环境 |

## 用户与入口脚本

默认容器用户为 `luciole`，默认命令为 `/bin/zsh`。配置的 `luciole` 账户 UID/GID 为 1000，具有免密 sudo 权限。工作目录为 `/home/luciole`。

身份由 Dockerfile 的 `USER` 决定，即使覆盖 ENTRYPOINT 也保持该身份。共享入口脚本通过 `sudo -n` 启动 sshd，然后 exec 用户命令。`APP_USER` 是描述性元数据，不控制权限；需要 root 会话时显式使用 `docker run --user root`。运行时不使用 gosu 降权。

## 构建参数

标准构建使用[清单](image.yml)中的值；直接构建仍可使用 Dockerfile 默认值。修改默认值时同步更新两者。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `BASE_IMAGE` | `ghcr.io/dkuav/luciole-cuda-base:${BASE_TAG}` | 直接构建的回退值；Bake 注入当前工作区的 base context |
| `BASE_TAG` | `latest` | 直接 Docker/Compose 构建的兼容参数 |
| `ROS_DISTRO` | `jazzy` | ROS 发行版 |
| `ROS_TARGET` | `ros-base` | ROS 安装目标 |
| `USERNAME` | `luciole` | 配置的账户名，必须与内部基础镜像一致 |

## 快速开始

```bash
docker pull ghcr.io/dkuav/luciole-cuda-dev:latest
docker run --rm -it --gpus all ghcr.io/dkuav/luciole-cuda-dev:latest
```

## 清单构建与测试

按[根文档](../../README_zh.md#本地构建与烟测)安装工具，ARM64 宿主机使用原生 `linux/arm64` 平台。

```bash
# 安装工具后在仓库根目录执行。
python -m tools.images plan --image luciole-cuda-dev --output build-plan.json
revision=$(git rev-parse HEAD)
python -m tools.images bake --plan build-plan.json --owner dkuav \
  --repository dkuav/images --revision "$revision" --platform linux/amd64 \
  --mode load --output docker-bake.load.json
docker buildx bake --file docker-bake.load.json
python -m tools.images test --plan build-plan.json --owner dkuav \
  --revision "$revision" --platform linux/amd64
```

Bake 流程构建当前工作区的依赖，只有显式选择的镜像标记为发布。Required：断言失败阻断发布。 Docker、构建或缺失脚本错误始终导致失败，包括 advisory 镜像。

## Compose 与直接构建

```bash
cd src/luciole-cuda-dev
docker compose build
# 在仓库根目录：
docker build -f src/luciole-cuda-dev/Dockerfile -t luciole-cuda-dev .
```

直接通过 Docker/Compose 构建最终镜像时，默认使用已发布的 base。验证当前工作区依赖时使用 Bake。Base Compose 仅用于构建；dev/runtime Compose 配置交互终端和 SSH `2222:22` 映射。

## SSH

```bash
docker run -dit --gpus all -p 2222:22 ghcr.io/dkuav/luciole-cuda-dev:latest
ssh -p 2222 luciole@localhost
```

现有配置启用 SSH 公钥认证和 root 登录。配置的 `luciole` 账户密码为 `123456`；root 密码继承上游，`user.sh` 不设置它。Host key 在构建时生成。Compose 映射宿主机 2222 端口；`docker compose run --rm --service-ports app` 会发布配置的端口。

## ROS 2 与 WSLg

ROS 不自动加载。在 zsh 中运行 `load_ros` 加载 `/opt/ros/jazzy/setup.zsh`，也可手动 source。Devshell 工具为 `luciole` 安装和配置。

Dev Compose 挂载 `/tmp/.X11-unix`、`/mnt/wslg`，转发 DISPLAY、WAYLAND_DISPLAY、XDG_RUNTIME_DIR、PULSE_SERVER，需要宿主机支持这些路径。

配置与发布细节见[构建架构](../../docs/build-architecture_zh.md)和[清单参考](../../docs/manifest-reference_zh.md)。
