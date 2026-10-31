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
| Python packages | uv, pytest tooling, FastAPI, pybind11, pandas, numpy, loguru and OpenCV wheels; see [pip-packages.sh](../_scripts/pip-packages.sh) |
| Networking libraries | libdatachannel v0.24.5, rpclib v2.3.0, iceoryx v2.0.8 |
| GUI | WSLg dependencies, D-Bus, CJK fonts, Mesa and PulseAudio |
| OpenCV | apt `libopencv-dev` plus pip packages; `opencv.sh` is disabled, so NVIDIA OpenCV is not quarantined by this Dockerfile |
| Mirrors | Upstream Ubuntu / PyPI sources; final images switch to Aliyun |
| Editor / timezone | `EDITOR=vim`, `VISUAL=vim`, default `Asia/Shanghai` |

## User and entrypoint

The default container user is `root` and the default command is `/bin/bash`. The configured `luciole` account has UID/GID 1000 and passwordless sudo. The base does not override the upstream working directory.

Dockerfile `USER` controls the identity, including when ENTRYPOINT is overridden. The shared entrypoint uses `sudo -n` to start sshd and then execs the command. `APP_USER` is descriptive metadata, not a privilege switch; use `docker run --user root` for an explicit root session. There is no runtime gosu privilege drop.

## Build arguments

The [manifest](image.yml) supplies these values for standard builds. Dockerfile defaults remain available for direct builds. Update both when changing defaults.

| Argument | Default | Meaning |
| --- | --- | --- |
| `BASE_IMAGE` | `nvcr.io/nvidia/pytorch:26.06-py3` | External base; manifest digest may pin it |
| `TZ` | `Asia/Shanghai` | Timezone |
| `CMAKE_VERSION` | `4.3.2` | CMake release |
| `LIBDATACHANNEL_VERSION` | `v0.24.5` | libdatachannel release |
| `RPCLIB_VERSION` | `v2.3.0` | rpclib release |
| `ICEORYX_VERSION` | `v2.0.8` | iceoryx release |
| `USERNAME` | `luciole` | Configured account; must match internal base |
| `USER_UID` | `1000` | Account UID |
| `USER_GID` | `1000` | Account GID; direct builds default to USER_UID |

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
docker run -dit --gpus all -p 2222:22 ghcr.io/dkuav/luciole-cuda-base:latest
ssh -p 2222 luciole@localhost
```

SSH public-key authentication and root login are enabled by the existing setup. The configured `luciole` account password is `123456`; root's password is inherited from upstream and is not set by `user.sh`. Host keys are generated during the build. Compose maps host port 2222; `docker compose run --rm --service-ports app` publishes configured ports.

## Known upstream issues

`opencv.sh` is currently disabled. Apt OpenCV is installed by dev-tools, but the Dockerfile does not quarantine NVIDIA's installation or guarantee that `find_package(OpenCV)` resolves to apt. Python packages are installed separately. The existing smoke assertions are preserved and may report differences.

Historical [OpenCV analysis](../../docs/opencv-status.md) and [linker diagnostics](../../docs/ld-cache-notes.md) contain evidence from specific older builds. This base Dockerfile currently has no HPC-X fixup step. The manual diagnostic workflow remains available; this build migration does not resolve upstream compatibility issues.

See [build architecture](../../docs/build-architecture.md) and [manifest reference](../../docs/manifest-reference.md) for configuration and release details.
