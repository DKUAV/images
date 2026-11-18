# Ascend Torch 推理服务镜像

本 ARM64 镜像基于 [ascend-peft](../ascend-peft/README_zh.md)，发布为 `ghcr.io/dkuav/ascend-torch-infer-server`。英文说明见 [README.md](README.md)。

## 依赖和运行方式

本镜像的 [requirements.txt](requirements.txt) 添加 `flask`、`flask-cors` 和 `minio`（MinIO Python SDK），并继承 PEFT、pycocotools、TensorBoard 及模型可视化依赖。镜像为应用提供推理服务依赖，默认命令沿用父镜像的 Bash；运行时需提供应用及启动命令。MinIO 对象存储服务单独运行。

该依赖文件还通过 SHA256 固定了官方 `aclruntime` 和 `ais_bench` 0.0.2 wheel。其中 `aclruntime` 原生 wheel 适用于 Linux ARM64 和 CPython 3.12。用法见 [Ascend AIS Bench 推理工具指南](https://gitee.com/ascend/tools/blob/master/ais-bench_workload/tool/ais_bench/README.md)。

安装前，Dockerfile 将父镜像全部已安装包版本记录到 `/opt/image-python/infer-server-constraints.txt`，并将其作为 pip 约束。这会保留 PEFT 软件栈，包括五个 Triton 辅助包版本，原始厂商约束文件保持不变。不兼容的依赖会使构建失败。安装后执行 `ascend-pip-check`，最后配置上游软件源并清理临时文件。

镜像继承 root、`HOME=/root`、`/work`、Ascend 入口和公钥 SSH 策略。宿主机 runtime、驱动要求和 SSH 凭据说明见 [Ascend 运行指南](../luciole-ascend/README_zh.md#使用-npu)。

## 构建与测试

在原生 ARM64 主机上，从仓库根目录执行：

```bash
git submodule update --init --recursive
uv sync --locked --extra dev
source .venv/bin/activate
python -m image_kit plan --target ascend-torch-infer-server/2.10.0.post7-cann9.2.0-infer-server-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

计划构建、测试当前工作区的 `luciole-ascend` 和 `ascend-peft` 两级父镜像，但不选择它们发布。新镜像使用 `ascend_peft` 命名上下文。修改任一级父镜像会选择下游镜像；仅修改本镜像的 requirements 时，只选择本镜像。

必须通过的烟测重跑两级父镜像检查，比较继承包版本与快照，调用 Flask CLI，通过 Flask 测试客户端验证 JSON 响应体和 CORS 响应头，在无网络访问的情况下初始化 MinIO 客户端，并执行 `python3 -m ais_bench --help` 检查 CLI 能否加载原生 ACL runtime。实际对象存储访问和模型推理需在兼容 NPU 主机上通过应用集成测试验证。另见独立的[硬件检查](../_tests/npu-ascend.sh)。

直接构建默认使用已发布的 `ascend-peft` 父镜像：

```bash
docker build -f src/ascend-torch-infer-server/Dockerfile -t ascend-torch-infer-server .
```

可通过 `BASE_TAG` 选择其他已发布的父镜像标签。发布使用 variant 通道 `2.10.0.post7-cann9.2.0-infer-server-910b-ubuntu22.04-py3.12`、不可覆盖的 `<variant>-<sha12>-<run-id>-<attempt>` 构建标签，以及从收据提升的 `<variant>-vMAJOR.MINOR.PATCH` 正式版本。

## 运行

无需 SSH 的交互会话：

```bash
IMAGE=ghcr.io/dkuav/ascend-torch-infer-server:2.10.0.post7-cann9.2.0-infer-server-910b-ubuntu22.04-py3.12
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

进入启用 NPU 的容器后，可用 `python3 -m ais_bench --model /work/model.om --device 0` 对 Ascend OM 模型进行基准测试。
