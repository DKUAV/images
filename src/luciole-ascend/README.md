# Luciole Ascend development image

This ARM64 image builds on `ascendai/torch-npu:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12` and publishes as `ghcr.io/dkuav/luciole-ascend`. The base tag is fixed, but its digest is deliberately not pinned. See the [Chinese guide](README_zh.md).

## Contents and build

The vendor base supplies Python 3.12, PyTorch 2.14, TorchNPU 2.14 and CANN. Shared scripts install system tools, CMake 4.3.2, the `luciole` account (UID/GID 1000), SSH and the development shell. Ascend-specific scripts preserve the vendor Python environment, install the packages in `src/_assets/python-dev-requirements.txt` under constraints generated from every preinstalled package, and restore CANN in login shells and the entrypoint. CUDA-specific pip, ROS 2 and networking library steps are not included.

The package check permits only three exact known vendor diagnostics: the `mindstudio-kl 26.2.0` NumPy bound and the two missing `ms-service-profiler 26.0.0` OTLP exporters. Other dependency errors fail the build. This does not establish compatibility for the affected vendor features. The image keeps upstream apt and pip sources.

Build and run smoke checks on a native ARM64 host:

```bash
python -m tools.images plan --image luciole-ascend --output build-plan.json
python -m tools.images bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m tools.images test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

Direct builds use the tagged vendor base by default and the repository root as context. Compose uses `context: ../..`. CI publishes `main`, `latest`, seven-character SHA and version tags after native checks pass. The required smoke test needs no NPU and does not verify hardware compatibility.

## Running with an NPU

Use an ARM64 host with a compatible Ascend 910B driver and Ascend Docker Runtime. Follow the [vendor compatibility information](https://www.hiascend.com/developer/download/compatibility) for host driver and CANN pairing. For example, with the `ascend` runtime registered:

```bash
IMAGE=ghcr.io/dkuav/luciole-ascend:latest
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

The default user is `luciole`, the work directory is `/work`, and the default command is Bash; the login shell is zsh. The default SSH mode is `password`, but the account is locked and no password is stored in the image. Set `SSH_MODE=disabled` when SSH is unnecessary. To enable key access, mount a nonempty `/home/luciole/.ssh/authorized_keys` and set `SSH_MODE=key-only`. To enable password access, mount a nonempty secret file and set `SSH_PASSWORD_FILE` to its container path. Publish port 22 only on a trusted interface. Root SSH login is disabled. The shared entrypoint starts sshd according to the mode and executes the command as the Dockerfile user.

The Compose example maps port `2222:22`; it does not provide credentials. The account remains locked until credentials are supplied at runtime. Hardware device mounts and runtime registration are host responsibilities.
