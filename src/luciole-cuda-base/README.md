# luciole-cuda-base

Shared NVIDIA PyTorch/CUDA base with system tools, GUI dependencies, Python packages, CMake, networking libraries and a configured user account.

> 中文文档：[README_zh.md](README_zh.md)

## Registry and platforms

`ghcr.io/dkuav/luciole-cuda-base:latest` — `linux/amd64` and `linux/arm64`.
Main also publishes `main` and `sha-<7-character-sha>`; `v*` events publish the version and SHA tags.

## Contents

| Category | Details |
| --- | --- |
| Base | `nvcr.io/nvidia/pytorch:26.06-py3`, with Python, PyTorch and CUDA supplied upstream |
| System / build | vim, Git/LFS, tmux, ripgrep, fd, bat, ffmpeg, GCC, Ninja, GDB, CMake 4.3.2 |
| Python packages | Shared [development requirements](../../vendor/image-kit/assets/python-dev-requirements.txt), including uv, ty and Ruff; CUDA-specific OpenCV and vision packages use [luciole-cuda-pip-packages.sh](../_scripts/python/luciole-cuda-pip-packages.sh). CUDA retains `numpy<2.0.0`. |
| Networking libraries | libdatachannel v0.24.5, rpclib v2.3.0, iceoryx v2.0.8 |
| GUI | WSLg dependencies, D-Bus, CJK fonts, Mesa and PulseAudio |
| OpenCV | apt `libopencv-dev` plus pip packages; `opencv.sh` is disabled, so NVIDIA OpenCV is not quarantined by this Dockerfile |
| Mirrors | Upstream Ubuntu / PyPI sources; final images switch to Aliyun |
| Editor / timezone | `EDITOR=vim`, `VISUAL=vim`, default `Asia/Shanghai` |

## User and entrypoint

The default container user is `root` and the default command is `/bin/bash`. The configured `luciole` account has UID/GID 1000 and passwordless sudo. The base does not override the upstream working directory.

Dockerfile `USER` controls identity, including when ENTRYPOINT is overridden. The shared entrypoint starts sshd according to `SSH_MODE` and then executes the command. Password mode is the default, but `luciole` is initially locked and the image has no password. Root SSH login is disabled with the default `DEFAULT_USER=luciole`. `APP_USER` is metadata; use `docker run --user root` for an explicit root session.

## Build arguments

The [manifest](image.yml) supplies these values for standard builds. Dockerfile defaults remain available for direct builds. Update both when changing defaults.

| Argument | Default | Meaning |
| --- | --- | --- |
| `BASE_IMAGE` | `nvcr.io/nvidia/pytorch:26.06-py3` | External base; manifest digest may pin it |
| `TZ` | `Asia/Shanghai` | Timezone |
| `SYSTEM_UPGRADE` | `true` | Upgrade installed packages during system initialization |
| `CMAKE_VERSION` | `4.3.2` | CMake release |
| `LIBDATACHANNEL_VERSION` | `v0.24.5` | libdatachannel release |
| `RPCLIB_VERSION` | `v2.3.0` | rpclib release |
| `ICEORYX_VERSION` | `v2.0.8` | iceoryx release |
| `USERNAME` | `luciole` | Configured account; must match internal base |
| `USER_UID` | `1000` | Account UID |
| `USER_GID` | `1000` | Account GID; direct builds default to USER_UID |
| `USER_GROUPS` | Empty | Comma-separated existing supplementary groups; root requires empty |

## Quick start

```bash
docker pull ghcr.io/dkuav/luciole-cuda-base:latest
docker run --rm -it --gpus all ghcr.io/dkuav/luciole-cuda-base:latest
```

## Manifest build and tests

Install tooling as described in the [root guide](../../README.md#local-build-and-smoke-tests). Use the native `linux/arm64` platform on ARM64 hosts.

```bash
# Run from the repository root after installing the tooling.
python -m tools.images plan --image luciole-cuda-base --output build-plan.json
revision=$(git rev-parse HEAD)
python -m tools.images bake --plan build-plan.json --owner dkuav \
  --repository dkuav/images --revision "$revision" --platform linux/amd64 \
  --mode load --output docker-bake.load.json
docker buildx bake --file docker-bake.load.json
python -m tools.images test --plan build-plan.json --owner dkuav \
  --revision "$revision" --platform linux/amd64
```

The Bake path builds the current checkout's dependencies. Only the explicitly selected image is marked for publication. Advisory: assertion failures are reported without blocking publication. Docker/build/missing-script errors always fail, including for advisory images.

## Compose and direct builds

```bash
cd src/luciole-cuda-base
docker compose build
# From the repository root:
docker build -f src/luciole-cuda-base/Dockerfile -t luciole-cuda-base .
```

Direct final-image Docker/Compose builds use the published base by default. Use Bake to validate same-checkout dependencies. Base Compose is build-only; dev/runtime Compose configure interactive terminals and map SSH `2222:22`.

## SSH

```bash
docker run -dit --gpus all -p 2222:22 -e SSH_PASSWORD_FILE=/run/secrets/ssh-password \
  -v "$HOME/.config/luciole/ssh-password:/run/secrets/ssh-password:ro" ghcr.io/dkuav/luciole-cuda-base:latest
ssh -p 2222 luciole@localhost
```

Before running this example, create a nonempty `$HOME/.config/luciole/ssh-password` file with restricted permissions. The default `SSH_MODE=password` starts sshd, but `luciole` is initially locked. For password access, mount a nonempty secret file and set `SSH_PASSWORD_FILE` to its container path. For key access, mount a nonempty `/home/luciole/.ssh/authorized_keys` and set `SSH_MODE=key-only`. Set `SSH_MODE=disabled` when SSH is unnecessary. Root SSH login is disabled with the default `DEFAULT_USER=luciole`; host keys are ensured at container startup. Publish port 22 only on a trusted interface. Compose maps host port 2222 without supplying credentials.

SSH follows the explicitly selected `DEFAULT_USER`: selecting `root` permits key-only root access with a nonempty `/root/.ssh/authorized_keys` by default; root password access requires a nonempty mounted `SSH_PASSWORD_FILE`. Root SSH grants full container privileges. Changing `DEFAULT_USER` at runtime selects the SSH account, not the Dockerfile command user.

## Known upstream issues

`opencv.sh` is currently disabled. Apt OpenCV is installed by dev-tools, but the Dockerfile does not quarantine NVIDIA's installation or guarantee that `find_package(OpenCV)` resolves to apt. Python packages are installed separately. The existing smoke assertions are preserved and may report differences.

Historical [OpenCV analysis](../../docs/opencv-status.md) and [linker diagnostics](../../docs/ld-cache-notes.md) contain evidence from specific older builds. This base Dockerfile currently has no HPC-X fixup step. The manual diagnostic workflow remains available; this build migration does not resolve upstream compatibility issues.

See [build architecture](../../docs/build-architecture.md) and [manifest reference](../../docs/manifest-reference.md) for configuration and release details.

The shared system installer still accepts `--timezone` and `--upgrade` through explicit Dockerfile arguments. The libdatachannel, rpclib and iceoryx installers take explicit `--version` arguments from the Dockerfile; their version environment variables are no longer read. `user.sh --groups` receives `USER_GROUPS` from the manifest. Referenced groups must already exist; an empty value adds no supplementary groups, and malformed lists or nonempty groups for root are rejected. Dev/runtime inherit these groups from the base.

Shared scripts and assets come from the commit-pinned `vendor/image-kit` submodule; Luciole extensions remain in `src/_scripts/` and `src/_assets/`. Manifests declare every copied input. Initialize the component with `git submodule update --init --recursive` before building.

The shared entrypoint is installed as `/usr/local/bin/docker-entrypoint`. Key-only mode requires nonempty `authorized_keys` by default. Explicit `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` allows sshd to start while waiting for a public key to be configured; an empty file does not enable unauthenticated login.

image-kit installs `gosu` and `sudo`; local `luciole-dev-tools.sh` adds `landscape-common`. CUDA dev/runtime inherit these tools from the base.

`SYSTEM_UPGRADE` defaults to `true` and is explicitly passed from the manifest and Dockerfile to component `system.sh --upgrade`. The local CUDA pip wrapper upgrades pip, then the component unconditionally reinstalls pip-managed psutil and resolves the common development requirements together with Luciole vision extensions.
