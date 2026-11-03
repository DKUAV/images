# Luciole 昇腾开发镜像

本 ARM64 镜像基于 `ascendai/torch-npu:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12`，发布为 `ghcr.io/dkuav/luciole-ascend`。基础镜像固定版本标签，但按要求不固定 digest。英文说明见 [README.md](README.md)。

## 内容与构建

厂商基础镜像提供 Python 3.12、PyTorch 2.14、TorchNPU 2.14 和 CANN。共享脚本安装系统工具、CMake 4.3.2、SSH 与开发 shell。镜像保留厂商 root 账号，HOME 为 `/root`，以读取仅 root 可访问的 CANN 脚本。两类镜像通过各自的 pip 安装脚本使用共用的 `vendor/image-kit/assets/python-dev-requirements.txt`，其中包括 uv、ty、Ruff、setuptools、setuptools-scm、Hatchling、hatch-vcs、editables 和 uv_build。昇腾脚本依据所有预装包生成的约束保留厂商 Python 环境，并在登录 shell 和入口脚本中恢复 CANN 环境。本镜像不安装 CUDA 专属视觉包、ROS 2 和网络库步骤。

共享开发工具包含 Graphviz 系统命令。PEFT 依赖以及 `graphviz`、`torchview` Python 包安装在派生的 [ascend-peft 镜像](../ascend-peft/README_zh.md)中。

依赖检查只放行三条精确匹配的厂商诊断：`mindstudio-kl 26.2.0` 对 NumPy 的版本要求，以及 `ms-service-profiler 26.0.0` 缺少两个 OTLP exporter。其他依赖错误会使构建失败；放行不代表相关厂商功能已经验证兼容。镜像保留上游 apt 和 pip 软件源。

在原生 ARM64 主机上构建和运行冒烟测试：

```bash
python -m image_kit plan --target luciole-ascend/2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

直接构建默认使用带版本标签的厂商基础镜像，并以仓库根目录为构建上下文。Compose 仅运行已发布镜像，不包含 `build` 字段；构建和测试当前工作区请使用上面的 manifest/Bake 命令。所有原生检查通过后，CI 发布显式 variant 和包含构建批次的标签。必过的冒烟测试不需要 NPU，也不证明硬件兼容。

## 使用 NPU

宿主机需要 ARM64、兼容的昇腾 910B 驱动及 Ascend Docker Runtime。请依据[厂商配套信息](https://www.hiascend.com/developer/download/compatibility)核对宿主机驱动和 CANN 版本。注册 `ascend` runtime 后，例如：

```bash
IMAGE=ghcr.io/dkuav/luciole-ascend:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

默认用户为 `root`，HOME 为 `/root`，工作目录为 `/work`，默认命令是 Bash，登录 shell 为 zsh。SSH 默认模式为 `key-only`，启动前需挂载非空的 `/root/.ssh/authorized_keys`，此模式关闭密码认证。不需要 SSH 时设置 `SSH_MODE=disabled`。显式选择 password 模式仍受支持，但必须在运行时挂载非空密码文件，并由 `SSH_PASSWORD_FILE` 指定容器内路径。root SSH 具有完整容器权限，仅向可信接口发布 22 端口。镜像层中不保存密码。

Compose 示例指定 `linux/arm64` 和 `runtime: ascend`，`ASCEND_VISIBLE_DEVICES` 未设置或为空时默认为 `0,1,2,3,4,5,6,7`，并分配 8 GiB 共享内存。宿主机 NPU 少于八张或只需使用部分设备时，请覆盖此列表（如 `0` 或 `0,1`）。宿主机 Ascend runtime 负责挂载选定的 NPU 设备及驱动。示例将 `src/luciole-ascend/mount/` 挂载到 `/work`，以 `sleep infinity` 保持运行，并在未手动停止时自动重启；同时将 `host.docker.internal` 指向宿主机网关，通过 `SYS_PTRACE` 和 `seccomp:unconfined` 支持调试。

示例映射 `2222:22`，将已有 SSH 配置目录只读挂载到 `/root/.ssh`。执行 `docker compose up` 前，将 `SSH_CONFIG_DIR` 设为该目录的宿主机路径；变量未设置或源目录不存在时 Compose 会报错。目录及其中的 `authorized_keys` 必须由 root 所有，权限分别为 `0700` 和 `0600`。使用容器专用目录，将客户端公钥复制到 `authorized_keys`；登录此容器所用的私钥保留在客户端。默认拒绝空公钥文件。例如，在 Linux 宿主机的仓库根目录执行：

```bash
docker info --format '{{json .Runtimes}}'  # 确认 ascend runtime 已注册。
sudo install -d -m 0700 /srv/luciole-ascend/ssh
sudo install -m 0600 ~/.ssh/id_ed25519.pub /srv/luciole-ascend/ssh/authorized_keys
export SSH_CONFIG_DIR=/srv/luciole-ascend/ssh
# 可选：export ASCEND_VISIBLE_DEVICES=0,1，覆盖默认的八张 NPU 配置。
docker compose -f src/luciole-ascend/docker-compose.yml pull
docker compose -f src/luciole-ascend/docker-compose.yml up -d
docker compose -f src/luciole-ascend/docker-compose.yml exec app npu-smi info
docker compose -f src/luciole-ascend/docker-compose.yml exec app zsh
```

更新镜像或重建容器时，宿主机目录会保留。请在宿主机修改内容；只读挂载不允许容器内写入，包括更新 SSH 客户端的 `known_hosts`。服务端身份密钥位于 `/etc/ssh/ssh_host_*`，不在此挂载范围内；保持服务端指纹不变需要单独持久化。设备挂载和 runtime 注册由宿主机负责。

SSH 使用显式选择的 `DEFAULT_USER`：选择 `root` 后，公钥模式默认要求非空的 `/root/.ssh/authorized_keys`；root 密码登录必须挂载非空的 `SSH_PASSWORD_FILE`。root SSH 具有完整容器权限。运行时修改 `DEFAULT_USER` 只选择 SSH 账户，不改变 Dockerfile 命令用户。

共享系统安装脚本支持 `--timezone` 和 `--upgrade`，Dockerfile 显式传递这两个参数。root 的清单不声明 UID/GID 或附加组，不重建或重新编号厂商账号。烟测通过 Bash 启动，恢复已安装的厂商环境，再显式测试真实 Ascend 入口及 SSH 凭据策略。

共享脚本和资产来自固定提交的 `vendor/image-kit` submodule；Luciole 扩展保留在 `src/_scripts/` 和 `src/_assets/`。清单声明每个复制输入，构建前先执行 `git submodule update --init --recursive`。

共享入口命令安装为 `/usr/local/bin/docker-entrypoint`。公钥模式默认要求非空 `authorized_keys`；显式设置 `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` 时，允许 sshd 先启动，等待后续配置公钥；空文件不允许无密钥登录。

公共工具中的 `gosu` 和 `sudo` 由 image-kit 安装，`landscape-common` 由本地 `luciole-dev-tools.sh` 补充；CUDA dev/runtime 从 base 继承。

`SYSTEM_UPGRADE` 仍为 `false`。Ascend 保留厂商 Python/CANN 约束，不调用 CUDA 的 psutil 和视觉扩展安装步骤。

清单通过 `variants[].tests[].library` 显式声明共享烟测辅助脚本；固定版本的 image-kit 包负责执行构建及烟测契约。

发布名称由 YAML `name` 决定，不要求与目录名相同，并使用显式 variant 通道。已验证构建标签为 `<variant>-<sha12>-<run-id>-<attempt>`；正式 `<variant>-vMAJOR.MINOR.PATCH` 标签从成功的 main 发布收据提升。所有必需原生任务通过后才更新公开标签，历史制品保留。
