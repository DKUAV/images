# luciole-cuda-dev

Development image extending base with ROS 2 Jazzy, LLVM 21, an interactive developer shell and cached pre-commit environments.

> 中文文档：[README_zh.md](README_zh.md)

## Registry and platforms

`ghcr.io/dkuav/luciole-cuda-dev:pytorch26.06-py3` — `linux/amd64` and `linux/arm64`.
Main advances the explicit variant channel. Build tags include variant, SHA12 and run ID/attempt; formal versions promote verified builds without rebuilding.

## Contents

| Category | Details |
| --- | --- |
| Base | [luciole-cuda-base](../luciole-cuda-base/README.md): PyTorch/CUDA, tools, pip packages, CMake, networking libraries and user |
| Python build tools | Inherited setuptools, setuptools-scm, Hatchling, hatch-vcs, editables, uv_build, wheel and packaging |
| ROS 2 | Jazzy `ros-base`, colcon, rosdep and rosinstall-generator |
| Mirrors | Aliyun apt/pip sources applied after all package installation; builds use upstream sources |
| SSH / GUI | SSH server and WSLg dependencies inherited from base |
| LLVM | LLVM 21: clang-format, clang-tidy and lldb |
| Developer shell | zsh, oh-my-zsh, NvChad/neovim with the shared ty Python LSP, starship, nvm, fzf, eza, zoxide, Atuin and Witr |
| Pre-commit | Hook environments pre-cached from the shared config |

## User and entrypoint

The default container user is `luciole` and the default command is `/bin/zsh`. The configured `luciole` account has UID/GID 1000 and passwordless sudo. The working directory is `/home/luciole`.

Dockerfile `USER` controls identity, including when ENTRYPOINT is overridden. The shared entrypoint starts sshd according to `SSH_MODE` and then executes the command. Password mode is the default, but `luciole` is initially locked and the image has no password. Root SSH login is disabled with the default `DEFAULT_USER=luciole`. `APP_USER` is metadata; use `docker run --user root` for an explicit root session.

## Build arguments

The [manifest](image.yml) supplies these values for standard builds. Dockerfile defaults remain available for direct builds. Update both when changing defaults.

| Argument | Default | Meaning |
| --- | --- | --- |
| `BASE_IMAGE` | `ghcr.io/dkuav/luciole-cuda-base:${BASE_TAG}` | Direct-build fallback; Bake supplies the same-checkout base context |
| `BASE_TAG` | `pytorch26.06-py3` | Compatibility argument for direct Docker/Compose builds |
| `ROS_DISTRO` | `jazzy` | ROS distribution |
| `ROS_TARGET` | `ros-base` | ROS installation target |
| `USERNAME` | `luciole` | Configured account; must match internal base |

## Quick start

```bash
docker pull ghcr.io/dkuav/luciole-cuda-dev:pytorch26.06-py3
docker run --rm -it --gpus all ghcr.io/dkuav/luciole-cuda-dev:pytorch26.06-py3
```

## Manifest build and tests

Install tooling as described in the [root guide](../../README.md#local-build-and-smoke-tests). Use the native `linux/arm64` platform on ARM64 hosts.

```bash
# Run from the repository root after installing the tooling.
python -m image_kit plan --target luciole-cuda-dev/pytorch26.06-py3 --output build-plan.json
revision=$(git rev-parse HEAD)
python -m image_kit bake --plan build-plan.json --owner dkuav \
  --repository dkuav/images --revision "$revision" --platform linux/amd64 \
  --mode load --output docker-bake.load.json
docker buildx bake --file docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav \
  --revision "$revision" --platform linux/amd64
```

The Bake path builds the current checkout's dependencies. Only the explicitly selected image is marked for publication. Required: assertion failures block publication. Docker/build/missing-script errors always fail, including for advisory images.

## Compose and direct builds

```bash
cd src/luciole-cuda-dev
docker compose build
# From the repository root:
docker build -f src/luciole-cuda-dev/Dockerfile -t luciole-cuda-dev .
```

Direct final-image Docker/Compose builds use the published base by default. Use Bake to validate same-checkout dependencies. Base Compose is build-only; dev/runtime Compose configure interactive terminals and map SSH `2222:22`.

## SSH

```bash
docker run -dit --gpus all -p 2222:22 -e SSH_PASSWORD_FILE=/run/secrets/ssh-password \
  -v "$HOME/.config/luciole/ssh-password:/run/secrets/ssh-password:ro" ghcr.io/dkuav/luciole-cuda-dev:pytorch26.06-py3
ssh -p 2222 luciole@localhost
```

Before running this example, create a nonempty `$HOME/.config/luciole/ssh-password` file with restricted permissions. The default `SSH_MODE=password` starts sshd, but `luciole` is initially locked. For password access, mount a nonempty secret file and set `SSH_PASSWORD_FILE` to its container path. For key access, mount a nonempty `/home/luciole/.ssh/authorized_keys` and set `SSH_MODE=key-only`. Set `SSH_MODE=disabled` when SSH is unnecessary. Root SSH login is disabled with the default `DEFAULT_USER=luciole`; host keys are ensured at container startup. Publish port 22 only on a trusted interface. Compose maps host port 2222 without supplying credentials.

SSH follows the explicitly selected `DEFAULT_USER`: selecting `root` permits key-only root access with a nonempty `/root/.ssh/authorized_keys` by default; root password access requires a nonempty mounted `SSH_PASSWORD_FILE`. Root SSH grants full container privileges. Changing `DEFAULT_USER` at runtime selects the SSH account, not the Dockerfile command user.

## ROS 2 and WSLg

ROS is not sourced automatically. Run `load_ros` in zsh to source `/opt/ros/jazzy/setup.zsh`, or source the setup file manually. Devshell tools are installed/configured for `luciole`.

Dev Compose mounts `/tmp/.X11-unix` and `/mnt/wslg` and forwards DISPLAY, WAYLAND_DISPLAY, XDG_RUNTIME_DIR and PULSE_SERVER. These paths require a compatible host environment.

See [build architecture](../../docs/build-architecture.md) and [manifest reference](../../docs/manifest-reference.md) for configuration and release details.

The Dockerfile passes manifest ROS values explicitly through `--distro` and `--target`, and the pre-commit config through `--config`; these installers no longer read their configuration environment variables. Supplementary user groups are configured by `USER_GROUPS` in the base manifest and inherited here.

Shared scripts and assets come from the commit-pinned `vendor/image-kit` submodule; Luciole extensions remain in `src/_scripts/` and `src/_assets/`. Manifests declare every copied input. Initialize the component with `git submodule update --init --recursive` before building.

The shared entrypoint is installed as `/usr/local/bin/docker-entrypoint`. Key-only mode requires nonempty `authorized_keys` by default. Explicit `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` allows sshd to start while waiting for a public key to be configured; an empty file does not enable unauthenticated login.

image-kit installs `gosu` and `sudo`; local `luciole-dev-tools.sh` adds `landscape-common`. CUDA dev/runtime inherit these tools from the base.

This image Dockerfile appends `load_ros` to the target user's Bash/zsh configuration after devshell setup, using the build-time `ROS_DISTRO`; shared devshell has no ROS-specific logic.

The manifest explicitly declares the shared smoke helper with `variants[].tests[].library`; the pinned image-kit package runs the build and smoke contract.

Publication uses YAML `name` independently of the directory and explicit variant channels. Verified build tags are `<variant>-<sha12>-<run-id>-<attempt>`; formal `<variant>-vMAJOR.MINOR.PATCH` tags promote an existing successful main publication receipt. All required native workers must pass before public tags advance. Historical tags remain available.
