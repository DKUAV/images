# Ascend Torch inference server image

This ARM64 image derives from [ascend-peft](../ascend-peft/README.md) and publishes as `ghcr.io/dkuav/ascend-torch-infer-server`. See the [Chinese guide](README_zh.md).

## Packages and runtime

Image-local [requirements.txt](requirements.txt) adds `flask`, `flask-cors`, and `minio` (the MinIO Python SDK). The image inherits the PEFT, pycocotools, TensorBoard and model visualization packages. It supplies dependencies for an application-provided inference server; its default command remains the parent's Bash shell. Supply your application and startup command when running it. MinIO object storage runs separately.

The same requirements pin the official `aclruntime` and `ais_bench` 0.0.2 wheels by SHA256. The native `aclruntime` wheel targets Linux ARM64 and CPython 3.12. See the [Ascend AIS Bench inference guide](https://gitee.com/ascend/tools/blob/master/ais-bench_workload/tool/ais_bench/README.md).

Before installing into the default Python environment, the Dockerfile records all installed parent versions in `/opt/image-python/infer-server-constraints.txt` and constrains pip to that snapshot. This preserves the PEFT stack, including its five Triton auxiliary versions, without changing the original vendor constraints. Incompatible dependencies fail the build. The default Python installation runs `ascend-pip-check`.

The build uses `uv` to create a separate Python 3.12 environment at `/opt/onnx` with `onnx`, `onnxruntime`, `onnxsim`, `onnxslim`, `onnxoptimizer`, `onnx-graphsurgeon`, `onnxconverter-common`, `onnxscript`, and `mindstudio-probe>=26.2.0`. The [environment requirements](onnx-requirements.txt) resolve independently of the default Python environment's vendor pins. The ARM64 build compiles `onnxoptimizer` from source when a wheel is unavailable. Installation finishes with upstream mirror configuration and cleanup.

Root, `HOME=/root`, `/work`, the Ascend entrypoint and key-only SSH are inherited. See the [Ascend runtime guide](../luciole-ascend/README.md#running-with-an-npu) for host runtime and driver requirements and SSH credentials.

## Build and test

Run from the repository root on a native ARM64 host:

```bash
git submodule update --init --recursive
uv sync --locked --extra dev
source .venv/bin/activate
python -m image_kit plan --target ascend-torch-infer-server/2.10.0.post7-cann9.2.0-infer-server-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

The plan builds and tests both current-checkout ancestors, `luciole-ascend` and `ascend-peft`, without selecting them for publication. The child uses the `ascend_peft` named context. Changes to either ancestor select downstream images. Changes to either of this image's requirements files select only this image.

Required smoke tests rerun both ancestors' checks, compare all inherited versions with the snapshot, invoke the Flask CLI, verify the JSON body and CORS response header through Flask's test client, initialize a MinIO client without network access, and run `python3 -m ais_bench --help` to check that the CLI loads the native ACL runtime. Live object storage and model inference require application integration tests on a compatible NPU host. See the separate [hardware check](../_tests/npu-ascend.sh).

The smoke test for `/opt/onnx` checks dependency consistency, runs `msprobe --help`, imports all eight ONNX packages, optimizes an in-memory ONNX graph and checks its output with ONNX Runtime's CPU execution provider.

Direct builds use the published `ascend-peft` parent by default:

```bash
docker build -f src/ascend-torch-infer-server/Dockerfile -t ascend-torch-infer-server .
```

Override `BASE_TAG` to select another published parent tag. Publication uses the variant channel `2.10.0.post7-cann9.2.0-infer-server-910b-ubuntu22.04-py3.12`, immutable `<variant>-<sha12>-<run-id>-<attempt>` build tags, and receipt-promoted `<variant>-vMAJOR.MINOR.PATCH` releases.

## Run

For an interactive session without SSH:

```bash
IMAGE=ghcr.io/dkuav/ascend-torch-infer-server:2.10.0.post7-cann9.2.0-infer-server-910b-ubuntu22.04-py3.12
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

Inside the NPU-enabled container, benchmark an Ascend OM model with `python3 -m ais_bench --model /work/model.om --device 0`.

Use `/opt/onnx/bin/python` for ONNX scripts and `/opt/onnx/bin/msprobe --help` to see the MindStudio Probe commands. Run `source /opt/onnx/bin/activate` in Bash to put both sets of tools on your shell's path. ONNX Runtime uses the CPU execution provider. Use this msProbe environment for offline analysis. In-process precision debugging requires msProbe, PyTorch, and TorchNPU in the same Python environment.
