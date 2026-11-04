# 昇腾 PEFT 镜像

本 ARM64 镜像基于 [luciole-ascend](../luciole-ascend/README_zh.md)，发布为 `ghcr.io/dkuav/ascend-peft`。英文说明见 [README.md](README.md)。

## 软件包

镜像通过本镜像的 [requirements.txt](requirements.txt) 添加 `accelerate==1.15.0`、`huggingface-hub`、`peft==0.21.2`、`transformers==5.22.1`、`tokenizers==0.23.3`、`torchvision`、`openai>=1.0`、`graphviz>=0.20`、`torchview>=0.2.7`、`torchmetrics`、`pillow`、`opencv-python`、`einops`、`triton-ascend==3.6.0` 和 `flash-linear-attention[npu]>=0.5`。setuptools、setuptools-scm、Hatchling、hatch-vcs、editables、uv_build、wheel 和 packaging 继承自父镜像的共享 Python 开发依赖。

TorchVision 固定为 `0.25.0+cpu`，与父镜像的 Torch 2.10.0 及 FLA 的 NPU extra 对齐。requirements 文件通过 `--extra-index-url` 添加 `https://download.pytorch.org/whl/cpu`，保留默认 PyPI 索引，并通过明确的 `+cpu` 版本选择 CPU wheel。附加索引作用于整次安装，父镜像的软件包约束仍然生效。此 CPU Torch/TorchNPU 栈需要使用 CPU wheel；CPU NMS 冒烟不代表已验证 NPU NMS 支持。

Dockerfile 根据父镜像的 `/opt/image-python/base-constraints.txt` 生成 `/opt/image-python/peft-constraints.txt`，只移除下表中 5 个辅助包的约束，原文件保持不变。安装时正常解析依赖，应用其余约束，并运行 `ascend-pip-check`；依赖不兼容时构建失败。Torch、TorchNPU、CANN 及其他已记录的父级包版本继续受到保护。包元数据检查沿用父镜像精确匹配的已知厂商例外，不代表 NPU 训练兼容性已经验证。镜像保持上游软件源。

### Flash Linear Attention

预编译的 Triton Ascend 3.6.0 wheel 在 Python 3.12 下要求以下辅助包版本。这些版本仅在子镜像的 requirements 中显式指定，父镜像保持不变。

| 软件包 | 子镜像版本 |
| --- | --- |
| attrs | 24.2.0 |
| numpy | 1.26.4 |
| scipy | 1.13.1 |
| decorator | 5.1.1 |
| psutil | 6.0.0 |

requirements 添加 Triton Ascend 官方索引，固定 `triton-ascend==3.6.0`，并选择 FLA 的 `[npu]` extra。解析器还会在必要时为 OpenCV、pandas、pytest 等应用或继承的开发依赖选择兼容版本，不使用 `--no-deps` 跳过依赖检查。[FLA 安装文档](https://github.com/fla-org/flash-linear-attention/blob/main/INSTALL.md)测试的 A2 软件栈为 Torch 2.10.0、TorchNPU 2.10.0.post7、TorchVision 0.25.0、Triton Ascend 3.6.0 和 CANN 9.1.0。本镜像保留 CANN 9.2.0，此组合仍需验证原生构建与 NPU 执行。

必过烟测会比较所有已记录的父级包版本，仅允许上述 5 个辅助包使用表中精确版本，并在无 NPU 设备时检查 Triton 版本、Ascend 后端和 FLA 线性注意力导入。这些检查不编译或执行 NPU kernel。在运行章节的硬件检查通过后，可在兼容的 NPU 宿主机上验证 FLA：

```bash
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" python3 - <<'PYTHON'
import torch
import torch_npu
from fla.ops.linear_attn import chunk_linear_attn

q, k, v = [torch.randn(1, 128, 2, 32, device="npu", dtype=torch.float16,
                       requires_grad=True) for _ in range(3)]
output, _ = chunk_linear_attn(q, k, v, normalize=False)
assert torch.isfinite(output).all().item()
output.float().sum().backward()
for tensor in (q, k, v):
    assert tensor.grad is not None and torch.isfinite(tensor.grad).all().item()
torch.npu.synchronize()
print("FLA NPU forward/backward passed")
PYTHON
```

镜像从父镜像的共享开发工具继承 Graphviz 的 `dot` 命令，Python 绑定支持 SVG 渲染，torchview 提供模型结构图。必过烟测会复跑父镜像的开发工具和 SSH 检查，将 Torch/TorchNPU 已安装版本与父级约束比较，检查应用包元数据，导入 TorchVision 并执行 CPU NMS，导入 OpenAI SDK，检查 pip 和 setuptools 一致性，在开启和关闭构建隔离时分别以 editable 模式安装临时 setuptools、setuptools-scm、Hatch/VCS 和 uv_build 项目，渲染 Graphviz SVG，并通过 torchview 绘制一个小型 CPU 模型。Editable 检查会从源码目录外导入模块，并验证源码修改能够生效；Hatch/VCS 和 setuptools-scm 项目会创建 Git 提交及 `v1.2.3` 标签，要求生成的版本文件和安装元数据均报告 `1.2.3`。非隔离检查显式校验构建依赖并关闭软件包索引，以验证预装工具能够离线工作。每种后端还会构建 sdist、从该 sdist 构建 wheel，再离线安装 wheel；导入必须来自源码目录之外，且版本符合预期。隔离构建需要访问索引获取构建依赖。这些检查无需 NPU；独立的[硬件检查](../_tests/npu-ascend.sh)需在兼容的 NPU 宿主机上运行。

源码项目的运行依赖已齐备时，可使用镜像自带的 Python 执行离线 editable 安装：`python3 -m pip install --no-index --no-deps --no-build-isolation --editable .`。预装构建工具不会让普通隔离构建自动支持离线。

## 构建与测试

在原生 ARM64 主机上，从仓库根目录执行：

```bash
git submodule update --init --recursive
uv sync --locked --extra dev
source .venv/bin/activate
python -m image_kit plan --target ascend-peft/2.10.0.post7-cann9.2.0-peft-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

计划通过 `ascend_base` 命名上下文构建、测试当前工作区的 `luciole-ascend` 父镜像，但不选择父镜像发布。仅修改 requirements 时选择子镜像；修改父镜像时也选择子镜像。CI 自动使用现有原生任务依赖图。

直接构建默认使用已发布的父镜像，以仓库根目录作为上下文：

```bash
docker build -f src/ascend-peft/Dockerfile -t ascend-peft .
```

可通过 `BASE_TAG` 选择其他已发布的父镜像标签。发布使用 variant 通道 `2.10.0.post7-cann9.2.0-peft-910b-ubuntu22.04-py3.12`、不可覆盖的 `<variant>-<sha12>-<run-id>-<attempt>` 构建标签，以及从收据提升的 `<variant>-vMAJOR.MINOR.PATCH` 正式版本。

## 运行

镜像继承 root、`HOME=/root`、`/work`、Bash、Ascend 入口和公钥 SSH 策略。无需 SSH 的交互会话：

```bash
IMAGE=ghcr.io/dkuav/ascend-peft:2.10.0.post7-cann9.2.0-peft-910b-ubuntu22.04-py3.12
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
