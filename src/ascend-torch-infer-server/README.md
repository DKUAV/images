# Ascend Torch inference server image

This ARM64 image derives from [ascend-peft](../ascend-peft/README.md) and publishes as `ghcr.io/dkuav/ascend-torch-infer-server`. See the [Chinese guide](README_zh.md).

## Packages and runtime

Image-local [requirements.txt](requirements.txt) adds `flask` and `minio` (the MinIO Python SDK). The image inherits the PEFT, pycocotools, TensorBoard and model visualization packages. It supplies dependencies for an application-provided inference server; its default command remains the parent's Bash shell. Supply your application and startup command when running it. MinIO object storage runs separately.

Before installing dependencies, the Dockerfile records all installed parent versions in `/opt/image-python/infer-server-constraints.txt` and constrains pip to that snapshot. This preserves the PEFT stack, including its five Triton auxiliary versions, without changing the original vendor constraints. Incompatible dependencies fail the build. Installation runs `ascend-pip-check` and finishes with upstream mirror configuration and cleanup.

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

The plan builds and tests both current-checkout ancestors, `luciole-ascend` and `ascend-peft`, without selecting them for publication. The child uses the `ascend_peft` named context. Changes to either ancestor select downstream images; changes to this image's requirements select only this image.

Required smoke tests rerun both ancestors' checks, compare all inherited versions with the snapshot, invoke the Flask CLI, handle a JSON request through Flask's test client, and initialize a MinIO client without network access. They do not exercise object storage or NPU inference. Run the separate [hardware check](../_tests/npu-ascend.sh) and application integration tests on a compatible NPU host.

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
