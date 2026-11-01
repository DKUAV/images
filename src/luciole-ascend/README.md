# Luciole Ascend development image

This ARM64 image builds on `ascendai/torch-npu:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12` and publishes as `ghcr.io/dkuav/luciole-ascend`. The base tag is fixed, but its digest is deliberately not pinned. See the [Chinese guide](README_zh.md).

## Contents and build

The vendor base supplies Python 3.12, PyTorch 2.14, TorchNPU 2.14 and CANN. Shared scripts install system tools, CMake 4.3.2, the `luciole` account (UID/GID 1000), SSH and the development shell. Both image families install the shared `vendor/image-kit/assets/python-dev-requirements.txt`, including uv, ty and Ruff, through separate pip scripts. Ascend's script preserves the vendor Python environment with constraints generated from every preinstalled package and restores CANN in login shells and the entrypoint. CUDA-specific vision packages, ROS 2 and networking library steps are not included.

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

The default user is `luciole`, the work directory is `/work`, and the default command is Bash; the login shell is zsh. The default SSH mode is `password`, but the account is locked and no password is stored in the image. Set `SSH_MODE=disabled` when SSH is unnecessary. To enable key access, mount a nonempty `/home/luciole/.ssh/authorized_keys` and set `SSH_MODE=key-only`. To enable password access, mount a nonempty secret file and set `SSH_PASSWORD_FILE` to its container path. Publish port 22 only on a trusted interface. Root SSH login is disabled with the default `DEFAULT_USER=luciole`. The shared entrypoint starts sshd according to the mode and executes the command as the Dockerfile user.

The Compose example maps port `2222:22`; it does not provide credentials. The account remains locked until credentials are supplied at runtime. Hardware device mounts and runtime registration are host responsibilities.

SSH follows the explicitly selected `DEFAULT_USER`: selecting `root` permits key-only root access with a nonempty `/root/.ssh/authorized_keys` by default; root password access requires a nonempty mounted `SSH_PASSWORD_FILE`. Root SSH grants full container privileges. Changing `DEFAULT_USER` at runtime selects the SSH account, not the Dockerfile command user.

The shared system installer accepts `--timezone` and `--upgrade`; Dockerfiles pass both values explicitly. The manifest build argument `DEFAULT_GROUPS` defaults to empty and is passed to `user.sh --groups`. Set it to comma-separated existing group names to add supplementary groups. Malformed lists and nonempty groups for root are rejected; default user, UID/GID and SSH mode are unchanged.

Shared scripts and assets come from the commit-pinned `vendor/image-kit` submodule; Luciole extensions remain in `src/_scripts/` and `src/_assets/`. Manifests declare every copied input. Initialize the component with `git submodule update --init --recursive` before building.

The shared entrypoint is installed as `/usr/local/bin/docker-entrypoint`. Key-only mode requires nonempty `authorized_keys` by default. Explicit `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` allows sshd to start while waiting for a public key to be configured; an empty file does not enable unauthenticated login.

image-kit installs `gosu`; local `luciole-dev-tools.sh` adds `landscape-common` and build-time `sudo`. CUDA dev/runtime inherit these tools from the base.

`SYSTEM_UPGRADE` remains `false`. Ascend preserves vendor Python/CANN constraints and does not run the CUDA psutil or vision-extension installation.
