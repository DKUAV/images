# Luciole Ascend development image

This ARM64 image builds on `ascendai/torch-npu:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12` and publishes as `ghcr.io/dkuav/luciole-ascend`. The base tag is fixed, but its digest is deliberately not pinned. See the [Chinese guide](README_zh.md).

## Contents and build

The vendor base supplies Python 3.12, PyTorch 2.14, TorchNPU 2.14 and CANN. Shared scripts install system tools, CMake 4.3.2, SSH and the development shell. The image retains the vendor root account and uses `/root` as HOME so root-owned CANN scripts remain readable. Both image families install the shared `vendor/image-kit/assets/python-dev-requirements.txt`, including uv, ty and Ruff, through separate pip scripts. Ascend's script preserves the vendor Python environment with constraints generated from every preinstalled package and restores CANN in login shells and the entrypoint. CUDA-specific vision packages, ROS 2 and networking library steps are not included.

The package check permits only three exact known vendor diagnostics: the `mindstudio-kl 26.2.0` NumPy bound and the two missing `ms-service-profiler 26.0.0` OTLP exporters. Other dependency errors fail the build. This does not establish compatibility for the affected vendor features. The image keeps upstream apt and pip sources.

Build and run smoke checks on a native ARM64 host:

```bash
python -m image_kit plan --target luciole-ascend/2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

Direct builds use the tagged vendor base by default and the repository root as context. Compose uses `context: ../..`. CI publishes explicit variant and batch-qualified build tags after all native checks pass. The required smoke test needs no NPU and does not verify hardware compatibility.

## Running with an NPU

Use an ARM64 host with a compatible Ascend 910B driver and Ascend Docker Runtime. Follow the [vendor compatibility information](https://www.hiascend.com/developer/download/compatibility) for host driver and CANN pairing. For example, with the `ascend` runtime registered:

```bash
IMAGE=ghcr.io/dkuav/luciole-ascend:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

The default user is `root`, HOME is `/root`, the work directory is `/work`, and the default command is Bash; the login shell is zsh. The default SSH mode is `key-only`; mount a nonempty `/root/.ssh/authorized_keys` before startup. Password authentication is disabled in this mode. Set `SSH_MODE=disabled` when SSH is unnecessary. Explicit password mode remains available and requires a nonempty runtime-mounted file referenced by `SSH_PASSWORD_FILE`. Root SSH grants full container privileges; publish port 22 only on a trusted interface. No password is stored in image layers.

The Compose example maps port `2222:22` and mounts an existing SSH configuration directory read-only at `/root/.ssh`. Set `SSH_CONFIG_DIR` to its host path before `docker compose up`; Compose fails if the variable is unset or the source directory is missing. The directory and its `authorized_keys` must be root-owned, with modes `0700` and `0600` respectively. Use a dedicated container directory and copy the client's public key into `authorized_keys`; private keys used to log into this container stay on the client. Empty keys are rejected by default. For example, from the repository root on a Linux host:

```bash
sudo install -d -m 0700 /srv/luciole-ascend/ssh
sudo install -m 0600 ~/.ssh/id_ed25519.pub /srv/luciole-ascend/ssh/authorized_keys
SSH_CONFIG_DIR=/srv/luciole-ascend/ssh docker compose -f src/luciole-ascend/docker-compose.yml up -d
```

The host directory survives image updates and container replacement. Edit it on the host; the read-only mount prevents changes from inside the container, including updates to SSH client `known_hosts`. Server identity keys live under `/etc/ssh/ssh_host_*`, outside this mount, so preserving the server fingerprint requires separate persistence. Hardware device mounts and runtime registration are host responsibilities.

SSH follows the explicitly selected `DEFAULT_USER`: selecting `root` permits key-only root access with a nonempty `/root/.ssh/authorized_keys` by default; root password access requires a nonempty mounted `SSH_PASSWORD_FILE`. Root SSH grants full container privileges. Changing `DEFAULT_USER` at runtime selects the SSH account, not the Dockerfile command user.

The shared system installer accepts `--timezone` and `--upgrade`; Dockerfiles pass both values explicitly. The manifest omits UID/GID and supplementary groups for root: the vendor account is neither recreated nor renumbered. Its smoke test starts through Bash, restores the installed vendor environment, and explicitly tests the real Ascend entrypoint and SSH credential policy.

Shared scripts and assets come from the commit-pinned `vendor/image-kit` submodule; Luciole extensions remain in `src/_scripts/` and `src/_assets/`. Manifests declare every copied input. Initialize the component with `git submodule update --init --recursive` before building.

The shared entrypoint is installed as `/usr/local/bin/docker-entrypoint`. Key-only mode requires nonempty `authorized_keys` by default. Explicit `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` allows sshd to start while waiting for a public key to be configured; an empty file does not enable unauthenticated login.

image-kit installs `gosu` and `sudo`; local `luciole-dev-tools.sh` adds `landscape-common`. CUDA dev/runtime inherit these tools from the base.

`SYSTEM_UPGRADE` remains `false`. Ascend preserves vendor Python/CANN constraints and does not run the CUDA psutil or vision-extension installation.

The manifest explicitly declares the shared smoke helper with `variants[].tests[].library`; the pinned image-kit package runs the build and smoke contract.

Publication uses YAML `name` independently of the directory and explicit variant channels. Verified build tags are `<variant>-<sha12>-<run-id>-<attempt>`; formal `<variant>-vMAJOR.MINOR.PATCH` tags promote an existing successful main publication receipt. All required native workers must pass before public tags advance. Historical tags remain available.
