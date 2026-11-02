# 昇腾 PEFT 镜像

本 ARM64 镜像基于 [luciole-ascend](../luciole-ascend/README_zh.md)，发布为 `ghcr.io/dkuav/ascend-peft`。英文说明见 [README.md](README.md)。

## 软件包

镜像通过本镜像的 [requirements.txt](requirements.txt) 添加 `accelerate`、`huggingface-hub`、`peft`、`transformers`、`torchvision`、`graphviz>=0.20` 和 `torchview>=0.2.7`。

共享 Ascend 应用安装器依据父镜像记录的 `/opt/image-python/base-constraints.txt` 解析依赖，并运行 `ascend-pip-check`。依赖不兼容时构建失败，不会替换父镜像中受约束的 Torch/TorchNPU 包。包元数据检查沿用父镜像精确匹配的已知厂商例外，不代表 NPU 训练兼容性已经验证。镜像保持上游软件源。

镜像从父镜像的共享开发工具继承 Graphviz 的 `dot` 命令，Python 绑定支持 SVG 渲染，torchview 提供模型结构图。必过烟测会复跑父镜像的开发工具和 SSH 检查，将 Torch/TorchNPU 已安装版本与父级约束比较，检查应用包元数据，导入 TorchVision 并执行 CPU NMS，检查 pip 和 setuptools 一致性，在开启和关闭构建隔离时分别以 editable 模式安装临时 setuptools 项目，渲染 Graphviz SVG，并通过 torchview 绘制一个小型 CPU 模型。Editable 检查会从源码目录外导入模块，并验证源码修改能够生效。隔离构建需要访问配置的软件包索引以获取构建依赖。这些检查无需 NPU；独立的[硬件检查](../_tests/npu-ascend.sh)需在兼容的 NPU 宿主机上运行。

## 构建与测试

在原生 ARM64 主机上，从仓库根目录执行：

```bash
git submodule update --init --recursive
uv sync --locked --extra dev
source .venv/bin/activate
python -m image_kit plan --target ascend-peft/2.14.0-cann9.2.0-peft-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

计划通过 `ascend_base` 命名上下文构建、测试当前工作区的 `luciole-ascend` 父镜像，但不选择父镜像发布。仅修改 requirements 时选择子镜像；修改父镜像时也选择子镜像。CI 自动使用现有原生任务依赖图。

直接构建默认使用已发布的父镜像，以仓库根目录作为上下文：

```bash
docker build -f src/ascend-peft/Dockerfile -t ascend-peft .
```

可通过 `BASE_TAG` 选择其他已发布的父镜像标签。发布使用 variant 通道 `2.14.0-cann9.2.0-peft-910b-ubuntu22.04-py3.12`、不可覆盖的 `<variant>-<sha12>-<run-id>-<attempt>` 构建标签，以及从收据提升的 `<variant>-vMAJOR.MINOR.PATCH` 正式版本。

## 运行

镜像继承 root、`HOME=/root`、`/work`、Bash、Ascend 入口和公钥 SSH 策略。无需 SSH 的交互会话：

```bash
IMAGE=ghcr.io/dkuav/ascend-peft:2.14.0-cann9.2.0-peft-910b-ubuntu22.04-py3.12
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

宿主机驱动、runtime 要求及 SSH 凭据说明见[父镜像运行指南](../luciole-ascend/README_zh.md#使用-npu)。本目录的 [Compose 配置](docker-compose.yml)运行已发布的子镜像，SSH 宿主机端口为 8101，将 `./mount` 挂载到 `/work`，默认暴露八张 NPU。请按宿主机设置 `ASCEND_VISIBLE_DEVICES`。将 `SSH_CONFIG_DIR` 设为已有的宿主机目录，其中必须包含非空 `authorized_keys`；目录和文件需由 root 所有，权限分别为 `0700` 和 `0600`。该目录只读挂载到 `/root/.ssh`。

```bash
export SSH_CONFIG_DIR=/srv/ascend-peft/ssh
export ASCEND_VISIBLE_DEVICES=0
docker compose -f src/ascend-peft/docker-compose.yml pull
docker compose -f src/ascend-peft/docker-compose.yml up -d
```
