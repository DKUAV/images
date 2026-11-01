# Luciole 昇腾开发镜像

本 ARM64 镜像基于 `ascendai/torch-npu:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12`，发布为 `ghcr.io/dkuav/luciole-ascend`。基础镜像固定版本标签，但按要求不固定 digest。英文说明见 [README.md](README.md)。

## 内容与构建

厂商基础镜像提供 Python 3.12、PyTorch 2.14、TorchNPU 2.14 和 CANN。共享脚本安装系统工具、CMake 4.3.2、`luciole` 账号（UID/GID 1000）、SSH 与开发 shell。两类镜像通过各自的 pip 安装脚本使用共用的 `vendor/image-kit/assets/python-dev-requirements.txt`，其中包括 uv、ty 和 Ruff。昇腾脚本依据所有预装包生成的约束保留厂商 Python 环境，并在登录 shell 和入口脚本中恢复 CANN 环境。本镜像不安装 CUDA 专属视觉包、ROS 2 和网络库步骤。

依赖检查只放行三条精确匹配的厂商诊断：`mindstudio-kl 26.2.0` 对 NumPy 的版本要求，以及 `ms-service-profiler 26.0.0` 缺少两个 OTLP exporter。其他依赖错误会使构建失败；放行不代表相关厂商功能已经验证兼容。镜像保留上游 apt 和 pip 软件源。

在原生 ARM64 主机上构建和运行冒烟测试：

```bash
python -m tools.images plan --image luciole-ascend --output build-plan.json
python -m tools.images bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m tools.images test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

直接构建默认使用带版本标签的厂商基础镜像，并以仓库根目录为构建上下文。Compose 使用 `context: ../..`。原生检查通过后，CI 发布 `main`、`latest`、七位 SHA 和版本标签。必过的冒烟测试不需要 NPU，也不证明硬件兼容。

## 使用 NPU

宿主机需要 ARM64、兼容的昇腾 910B 驱动及 Ascend Docker Runtime。请依据[厂商配套信息](https://www.hiascend.com/developer/download/compatibility)核对宿主机驱动和 CANN 版本。注册 `ascend` runtime 后，例如：

```bash
IMAGE=ghcr.io/dkuav/luciole-ascend:latest
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

默认用户为 `luciole`，工作目录为 `/work`，默认命令是 Bash，登录 shell 为 zsh。SSH 默认模式是 `password`，但账号初始锁定，镜像中没有密码。不需要 SSH 时设置 `SSH_MODE=disabled`。使用公钥时挂载非空的 `/home/luciole/.ssh/authorized_keys` 并设置 `SSH_MODE=key-only`；使用密码时挂载非空的密码密钥文件，并将 `SSH_PASSWORD_FILE` 设为容器内路径。仅向可信接口发布 22 端口；默认 `DEFAULT_USER=luciole` 时禁止 root SSH 登录。共享入口脚本按模式启动 sshd，再以 Dockerfile 用户执行命令。

Compose 示例映射 `2222:22`，不提供凭据；运行时提供凭据前账号保持锁定。设备挂载和 runtime 注册由宿主机负责。

SSH 使用显式选择的 `DEFAULT_USER`：选择 `root` 后，公钥模式默认要求非空的 `/root/.ssh/authorized_keys`；root 密码登录必须挂载非空的 `SSH_PASSWORD_FILE`。root SSH 具有完整容器权限。运行时修改 `DEFAULT_USER` 只选择 SSH 账户，不改变 Dockerfile 命令用户。

共享系统安装脚本支持 `--timezone` 和 `--upgrade`；Dockerfile 显式传递这两个参数。清单构建参数 `DEFAULT_GROUPS` 默认为空，并传给 `user.sh --groups`；可设置为逗号分隔的已有组名以添加附加用户组。格式错误的列表和 root 的非空附加组会被拒绝；默认用户、UID/GID 与 SSH 模式保持不变。

共享脚本和资产来自固定提交的 `vendor/image-kit` submodule；Luciole 扩展保留在 `src/_scripts/` 和 `src/_assets/`。清单声明每个复制输入，构建前先执行 `git submodule update --init --recursive`。

共享入口命令安装为 `/usr/local/bin/docker-entrypoint`。公钥模式默认要求非空 `authorized_keys`；显式设置 `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` 时，允许 sshd 先启动，等待后续配置公钥；空文件不允许无密钥登录。

公共工具中的 `gosu` 和 `sudo` 由 image-kit 安装，`landscape-common` 由本地 `luciole-dev-tools.sh` 补充；CUDA dev/runtime 从 base 继承。

`SYSTEM_UPGRADE` 仍为 `false`。Ascend 保留厂商 Python/CANN 约束，不调用 CUDA 的 psutil 和视觉扩展安装步骤。
