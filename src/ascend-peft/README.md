# Ascend PEFT image

This ARM64 image derives from [luciole-ascend](../luciole-ascend/README.md) and publishes as `ghcr.io/dkuav/ascend-peft`. See the [Chinese guide](README_zh.md).

## Packages

The image adds `accelerate==1.15.0`, `huggingface-hub`, `peft==0.21.2`, `transformers==5.22.1`, `tokenizers==0.23.3`, `torchvision`, `openai>=1.0`, `graphviz>=0.20`, `torchview>=0.2.7`, `torchmetrics`, `pillow`, `opencv-python`, `einops`, `triton-ascend==3.6.0` and `flash-linear-attention[npu]>=0.5` through image-local [requirements.txt](requirements.txt). It inherits setuptools, setuptools-scm, Hatchling, hatch-vcs, editables, uv_build, wheel and packaging from the parent's shared Python development requirements.

TorchVision is pinned to `0.25.0+cpu`, matching the parent's Torch 2.10.0 and FLA's NPU extra. The requirements file adds `https://download.pytorch.org/whl/cpu` with `--extra-index-url`, keeping the default PyPI index available; the explicit `+cpu` version selects the CPU wheel. The extra index applies to the entire installation, while the parent's package constraints remain enforced. A CPU wheel is required for this CPU Torch/TorchNPU stack. The CPU NMS smoke check does not establish NPU NMS support.

The Dockerfile derives `/opt/image-python/peft-constraints.txt` from the parent's `/opt/image-python/base-constraints.txt`, removing only the five auxiliary pins listed below. The original file stays unchanged. Installation resolves dependencies normally against the remaining constraints and runs `ascend-pip-check`; incompatible requirements fail the build. Torch, TorchNPU, CANN and all other recorded parent package versions remain protected. Package metadata checks retain the parent's exact known vendor exceptions; they do not establish NPU training compatibility. The image keeps upstream package sources.

### Flash Linear Attention

The precompiled Triton Ascend 3.6.0 wheel requires the following auxiliary versions on Python 3.12. These are explicit requirements of this child image; the parent image is unchanged.

| Package | Child version |
| --- | --- |
| attrs | 24.2.0 |
| numpy | 1.26.4 |
| scipy | 1.13.1 |
| decorator | 5.1.1 |
| psutil | 6.0.0 |

The requirements file adds the official Triton Ascend index, pins `triton-ascend==3.6.0`, and selects FLA's `[npu]` extra. The installation passes both the application requirements and the parent's shared development requirements to the same pip resolver. This allows compatible versions of inherited tools and their dependencies, including IPython and contourpy, to be selected for the older psutil and NumPy pins; pip does not automatically repair unrelated installed packages when only the application list is requested. The remaining parent constraints and `ascend-pip-check` still apply. It does not bypass dependencies with `--no-deps`. See the [FLA installation guide](https://github.com/fla-org/flash-linear-attention/blob/main/INSTALL.md): its tested A2 stack uses Torch 2.10.0, TorchNPU 2.10.0.post7, TorchVision 0.25.0, Triton Ascend 3.6.0 and CANN 9.1.0. This image retains CANN 9.2.0; native build and NPU execution must be verified for this combination.

Required smoke tests compare every recorded parent package against its original version, except for the five exact auxiliary versions above, and check the Triton version, Ascend backend and FLA linear-attention imports without NPU devices. They do not compile or execute an NPU kernel. After the hardware check in the Run section, test FLA on a compatible NPU host with:

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

The image inherits Graphviz's `dot` executable from the parent's shared developer tools. Its Python binding supports SVG rendering; torchview provides model graphs. Required smoke tests rerun the parent's development and SSH checks, compare installed Torch/TorchNPU versions with the parent's recorded constraints, check application package metadata, import TorchVision and execute CPU NMS, import the OpenAI SDK, verify pip and setuptools consistency, install temporary setuptools, setuptools-scm, Hatch/VCS and uv_build projects in editable mode with and without build isolation, render Graphviz SVG, and draw a small CPU model with torchview. Editable checks import from outside the source directory and verify that source edits take effect. Hatch/VCS and setuptools-scm fixtures create a Git commit tagged `v1.2.3` and require both the generated version file and installed metadata to report `1.2.3`. Non-isolated checks explicitly validate build dependencies and disable package indexes to verify the prepared build tools work offline. Each backend also builds an sdist, builds a wheel from that sdist, and installs the wheel offline; imports must resolve outside the source checkout and report the expected version. Isolated builds need index access for build dependencies. These checks require no NPU. Run the separate [hardware check](../_tests/npu-ascend.sh) on a compatible NPU host.

For an offline editable install of a source project whose runtime dependencies are already present, use the image's Python with `python3 -m pip install --no-index --no-deps --no-build-isolation --editable .`. Preinstalled build tools do not make an ordinary isolated build offline.

## Build and test

Run from the repository root on a native ARM64 host:

```bash
git submodule update --init --recursive
uv sync --locked --extra dev
source .venv/bin/activate
python -m image_kit plan --target ascend-peft/2.10.0.post7-cann9.2.0-peft-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

The plan builds and tests the current checkout's `luciole-ascend` parent through the `ascend_base` named context, without selecting the parent for publication. A requirements-only change selects the child; a parent change also selects the child. CI uses the existing native worker graph automatically.

Direct builds use the published parent by default and the repository root as context:

```bash
docker build -f src/ascend-peft/Dockerfile -t ascend-peft .
```

Override `BASE_TAG` to select another published parent tag. Publication uses the variant channel `2.10.0.post7-cann9.2.0-peft-910b-ubuntu22.04-py3.12`, immutable `<variant>-<sha12>-<run-id>-<attempt>` build tags, and receipt-promoted `<variant>-vMAJOR.MINOR.PATCH` releases.

## Run

The image inherits root, `HOME=/root`, `/work`, Bash, the Ascend entrypoint and key-only SSH. For an interactive session without SSH:

```bash
IMAGE=ghcr.io/dkuav/ascend-peft:2.10.0.post7-cann9.2.0-peft-910b-ubuntu22.04-py3.12
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

See the [parent runtime guide](../luciole-ascend/README.md#running-with-an-npu) for host driver/runtime requirements and SSH credentials. The local [Compose configuration](docker-compose.yml) runs the published child, exposes SSH on port 8101, mounts `./mount` at `/work`, and defaults to eight visible NPUs. Set `ASCEND_VISIBLE_DEVICES` for your host. Set `SSH_CONFIG_DIR` to an existing host directory containing a nonempty `authorized_keys`; the directory and file must be root-owned with modes `0700` and `0600`. The directory is mounted read-only at `/root/.ssh`.

```bash
export SSH_CONFIG_DIR=/srv/ascend-peft/ssh
export ASCEND_VISIBLE_DEVICES=0
docker compose -f src/ascend-peft/docker-compose.yml pull
docker compose -f src/ascend-peft/docker-compose.yml up -d
```
