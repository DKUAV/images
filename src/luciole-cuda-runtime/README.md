# luciole-cuda-runtime

Runtime image extending base with ROS 2 Jazzy. It inherits system development tools, Python packages, CMake and networking libraries; it omits the dev-only shell and LLVM additions.

> 中文文档：[README_zh.md](README_zh.md)

## Registry and platforms

`ghcr.io/dkuav/luciole-cuda-runtime:latest` — `linux/amd64` and `linux/arm64`.
Main also publishes `main` and `sha-<7-character-sha>`; `v*` events publish the version and SHA tags.

## Contents

| Category | Details |
| --- | --- |
| Base | [luciole-cuda-base](../luciole-cuda-base/README.md): PyTorch/CUDA, tools, pip packages, CMake, networking libraries and user |
| ROS 2 | Jazzy `ros-base`, colcon, rosdep and rosinstall-generator |
| Mirrors | Aliyun apt/pip sources applied after all package installation; builds use upstream sources |
| SSH / GUI | SSH server and WSLg dependencies inherited from base |

## User and entrypoint

The default container user is `luciole` and the default command is `/bin/bash`. The configured `luciole` account has UID/GID 1000 and passwordless sudo. The working directory is `/home/luciole`.

Dockerfile `USER` controls the identity, including when ENTRYPOINT is overridden. The shared entrypoint uses `sudo -n` to start sshd and then execs the command. `APP_USER` is descriptive metadata, not a privilege switch; use `docker run --user root` for an explicit root session. There is no runtime gosu privilege drop.

## Build arguments

The [manifest](image.yml) supplies these values for standard builds. Dockerfile defaults remain available for direct builds. Update both when changing defaults.

| Argument | Default | Meaning |
| --- | --- | --- |
| `BASE_IMAGE` | `ghcr.io/dkuav/luciole-cuda-base:${BASE_TAG}` | Direct-build fallback; Bake supplies the same-checkout base context |
| `BASE_TAG` | `latest` | Compatibility argument for direct Docker/Compose builds |
| `ROS_DISTRO` | `jazzy` | ROS distribution |
| `ROS_TARGET` | `ros-base` | ROS installation target |
| `USERNAME` | `luciole` | Configured account; must match internal base |

## Quick start

```bash
docker pull ghcr.io/dkuav/luciole-cuda-runtime:latest
docker run --rm -it --gpus all ghcr.io/dkuav/luciole-cuda-runtime:latest
```

## Manifest build and tests

Install tooling as described in the [root guide](../../README.md#local-build-and-smoke-tests). Use the native `linux/arm64` platform on ARM64 hosts.

```bash
# Run from the repository root after installing the tooling.
python -m tools.images plan --image luciole-cuda-runtime --output build-plan.json
revision=$(git rev-parse HEAD)
python -m tools.images bake --plan build-plan.json --owner dkuav \
  --repository dkuav/images --revision "$revision" --platform linux/amd64 \
  --mode load --output docker-bake.load.json
docker buildx bake --file docker-bake.load.json
python -m tools.images test --plan build-plan.json --owner dkuav \
  --revision "$revision" --platform linux/amd64
```

The Bake path builds the current checkout's dependencies. Only the explicitly selected image is marked for publication. Required: assertion failures block publication. Docker/build/missing-script errors always fail, including for advisory images.

## Compose and direct builds

```bash
cd src/luciole-cuda-runtime
docker compose build
# From the repository root:
docker build -f src/luciole-cuda-runtime/Dockerfile -t luciole-cuda-runtime .
```

Direct final-image Docker/Compose builds use the published base by default. Use Bake to validate same-checkout dependencies. Base Compose is build-only; dev/runtime Compose configure interactive terminals and map SSH `2222:22`.

## SSH

```bash
docker run -dit --gpus all -p 2222:22 ghcr.io/dkuav/luciole-cuda-runtime:latest
ssh -p 2222 luciole@localhost
```

SSH public-key authentication and root login are enabled by the existing setup. The configured `luciole` account password is `123456`; root's password is inherited from upstream and is not set by `user.sh`. Host keys are generated during the build. Compose maps host port 2222; `docker compose run --rm --service-ports app` publishes configured ports.

## ROS 2 setup

Source `source /opt/ros/jazzy/setup.bash` before using ROS. Runtime does not add devshell, the `load_ros` alias or LLVM; its default command remains Bash.

See [build architecture](../../docs/build-architecture.md) and [manifest reference](../../docs/manifest-reference.md) for configuration and release details.
