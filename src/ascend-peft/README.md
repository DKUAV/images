# Ascend PEFT image

This ARM64 image derives from [luciole-ascend](../luciole-ascend/README.md) and publishes as `ghcr.io/dkuav/ascend-peft`. See the [Chinese guide](README_zh.md).

## Packages

The image adds `accelerate`, `huggingface-hub`, `peft`, `transformers`, `torchvision`, `openai>=1.0`, `graphviz>=0.20`, `torchview>=0.2.7`, `torchmetrics`, `pillow`, `opencv-python`, `einops` and `flash-linear-attention>=0.5` through image-local [requirements.txt](requirements.txt). It inherits setuptools, setuptools-scm, Hatchling, hatch-vcs, editables, uv_build, wheel and packaging from the parent's shared Python development requirements.

TorchVision is pinned to `0.29.0+cpu`, matching the parent's Torch 2.14.0 and Minifly's Ascend extra. The requirements file adds `https://download.pytorch.org/whl/cpu` with `--extra-index-url`, keeping the default PyPI index available; the explicit `+cpu` version selects the CPU wheel. The extra index applies to the entire installation, while the parent's package constraints remain enforced. A CPU wheel is required for this CPU Torch/TorchNPU stack. The CPU NMS smoke check does not establish NPU NMS support.

The shared Ascend application installer resolves these packages against `/opt/image-python/base-constraints.txt` recorded by the parent and runs `ascend-pip-check`. An incompatible dependency resolution fails the build instead of replacing the parent's constrained Torch/TorchNPU packages. Package metadata checks retain the parent's exact known vendor exceptions; they do not establish NPU training compatibility. The image keeps upstream package sources.

### Flash Linear Attention

[install-triton-ascend.sh](install-triton-ascend.sh) builds Triton Ascend from upstream commit [`b3c899b8de4a1061d93f710262ef46e61e4ab4a0`](https://github.com/triton-lang/triton-ascend/commit/b3c899b8de4a1061d93f710262ef46e61e4ab4a0), including its pinned AscendNPU-IR dialect sources. This revision relaxes the runtime dependency pins that make the published 3.6.0.post2 wheel conflict with the parent's attrs, NumPy and other packages. The source wheel is installed with normal dependency resolution and the complete parent constraints, followed by `ascend-pip-check`. Its upstream `triton==3.6.0` dependency installs before the Ascend backend, which supplies the final `triton` module files.

The build uses Clang/LLD 15, limits compilation to two jobs and linking to one job, and installs CMake 3.x in the temporary PEP 517 build environment. The image retains CMake 4.3.2. Source, build files and downloaded LLVM tools are removed after installation. Native ARM64 builds require access to GitHub, GitCode, PyPI and the upstream LLVM artifact host. Runtime compilation uses `bishengir-compile` from the parent's CANN environment; it does not rebuild the full AscendNPU-IR compiler.

FLA is installed without a backend extra because the [upstream NPU extra](https://github.com/fla-org/flash-linear-attention/blob/main/INSTALL.md#ascend-npu) pins Torch 2.10.0, TorchNPU 2.10.0.post7 and TorchVision 0.25.0. The image supplies its existing Torch 2.14.0/TorchNPU 2.14.0/CANN 9.2.0 stack and the source-built backend explicitly. The `>=0.5` floor excludes older FLA packages with implicit CUDA dependencies. This stack is outside upstream FLA's documented NPU combination and requires validation on the target NPU host.

Required smoke tests verify every recorded parent package version, the compiled Ascend backend, the CANN compiler executable, and FLA/kernel imports without NPU devices. These checks do not execute an NPU attention kernel. On a compatible NPU host, first run the hardware check below, then exercise a small FLA forward/backward pass:

```bash
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" python3 - <<'PYTHON'
import torch
import torch_npu
from fla.ops.linear_attn import chunk_linear_attn

q, k, v = [torch.randn(1, 128, 2, 32, device="npu", dtype=torch.float16,
                       requires_grad=True) for _ in range(3)]
output, _ = chunk_linear_attn(q, k, v, normalize=False)
assert torch.isfinite(output).all()
output.float().square().mean().backward()
torch.npu.synchronize()
for tensor in (q, k, v):
    assert tensor.grad is not None and torch.isfinite(tensor.grad).all()
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
python -m image_kit plan --target ascend-peft/2.14.0-cann9.2.0-peft-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

The plan builds and tests the current checkout's `luciole-ascend` parent through the `ascend_base` named context, without selecting the parent for publication. A requirements-only change selects the child; a parent change also selects the child. CI uses the existing native worker graph automatically.

Direct builds use the published parent by default and the repository root as context:

```bash
docker build -f src/ascend-peft/Dockerfile -t ascend-peft .
```

Override `BASE_TAG` to select another published parent tag. Publication uses the variant channel `2.14.0-cann9.2.0-peft-910b-ubuntu22.04-py3.12`, immutable `<variant>-<sha12>-<run-id>-<attempt>` build tags, and receipt-promoted `<variant>-vMAJOR.MINOR.PATCH` releases.

## Run

The image inherits root, `HOME=/root`, `/work`, Bash, the Ascend entrypoint and key-only SSH. For an interactive session without SSH:

```bash
IMAGE=ghcr.io/dkuav/ascend-peft:2.14.0-cann9.2.0-peft-910b-ubuntu22.04-py3.12
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
