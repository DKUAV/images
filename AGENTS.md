# DKUAV Images — Agent Instructions

This repository manages Docker images for the DKUAV project. Images are published to GitHub Container Registry (`ghcr.io/dkuav/<image>`).

## Repository Layout

```
src/
  _scripts/               # Shared installation scripts (01–10)
  _assets/                # Shared assets (e.g. pre-commit config)
  image-deps.json         # CI dependency + arch-override map
  <image-name>/           # One subdirectory per image
    Dockerfile            # Required (CI uses this to detect image directories)
    docker-compose.yml    # Optional, for local build/run
    README.md             # Optional, image documentation
    README_zh.md          # Optional, image documentation (Chinese)
.github/workflows/
  publish-images.yml      # CI: detect changes → multi-arch build → merge manifest
```

## Image Naming Convention

`src/<image-name>` → `ghcr.io/dkuav/<image-name>`

- Directory name becomes the image name. **Do not** use uppercase letters or spaces.
- Example: `src/luciole-humble-dev` → `ghcr.io/dkuav/luciole-humble-dev`

## Build Context

All Dockerfiles use the **repository root** (`.`) as the Docker build context so that `COPY src/_scripts/` works. `docker-compose.yml` files therefore set `context: ../..` and `dockerfile: src/<image-name>/Dockerfile`.

## Shared Scripts (`src/_scripts/`)

Numbered shell scripts that encapsulate all reusable installation logic:

| Script | Purpose | Used by |
|--------|---------|---------|
| `system.sh` | Apt upgrade, timezone, locale — minimal system bootstrap | All base images |
| `dev-tools.sh` | Developer CLI toolset (editors, VCS, build, debug, ffmpeg) — run right after `system.sh` | All base images |
| `wslg.sh` | GUI / WSLg deps (D-Bus, CJK fonts, Mesa, PulseAudio) — run after `dev-tools.sh` | All base images |
| `python-install.sh` | Python 3.10 from apt + pip bootstrap | `luciole-base` only (pytorch/l4t already have Python) |
| `pip-packages.sh` | pip packages, uv, aliyun mirror | All base images |
| `ros2.sh` | ROS 2 (reads `$ROS_DISTRO`, `$ROS_TARGET`) | All final images |
| `cmake.sh` | Newer CMake binary release (reads `$CMAKE_VERSION`) | All final images |
| `clang.sh` | LLVM 21 (clang-format, clang-tidy, lldb) | Dev final images only |
| `user.sh` | Non-root user + sudo (reads `$USERNAME`, `$USER_UID`) | All base images |
| `devshell.sh` | zsh, oh-my-zsh, neovim, starship, nvm, … | Dev final images only — **must run as target user** |
| `precommit.sh` | Pre-cache pre-commit hook environments from `_assets/.pre-commit-config.yaml` | Dev final images only — **must run as target user** |

Each Dockerfile does `COPY src/_scripts/ /tmp/scripts/ && chmod +x /tmp/scripts/*.sh`, runs the required scripts, then `RUN rm -rf /tmp/scripts`. Dev images also `COPY src/_assets/ /tmp/assets/` for `precommit.sh`.

## Two-Tier Image Architecture

### Tier 1 — Base Images (published to GHCR, used as FROM in Tier 2)

| Directory | Base FROM | Description |
|-----------|-----------|-------------|
| `src/luciole-base` | `mcr.microsoft.com/devcontainers/base:ubuntu22.04` | Ubuntu 22.04 + Python + pip packages + user (amd64 only) |
| `src/luciole-cuda-base` | `nvcr.io/nvidia/pytorch:24.10-py3` | PyTorch/CUDA + pip packages + user (amd64 only) |
| `src/luciole-l4t-base` | `nvcr.io/nvidia/l4t-tensorrt:r10.3.0-devel` | L4T TensorRT + pip packages + user (arm64 only) |

### Tier 2 — Final Images (depend on Tier 1 base images)

| Directory | FROM (Tier 1) | Arch | Description |
|-----------|---------------|------|-------------|
| `src/luciole-humble-dev` | `luciole-base` | amd64 only | Ubuntu dev: ROS 2 + devtools + devshell |
| `src/luciole-humble-cuda-dev` | `luciole-cuda-base` | amd64 only | CUDA dev: ROS 2 + devtools + devshell |
| `src/luciole-humble-cuda-runtime` | `luciole-cuda-base` | amd64 only | CUDA runtime: ROS 2 + cmake only |
| `src/luciole-humble-l4t-dev` | `luciole-l4t-base` | arm64 only | L4T dev: ROS 2 + devtools + devshell |
| `src/luciole-humble-l4t-runtime` | `luciole-l4t-base` | arm64 only | L4T runtime: ROS 2 + cmake only |

## `src/image-deps.json`

Drives CI change detection and dependency propagation:

```json
{
  "base_images": ["luciole-base", "luciole-cuda-base", "luciole-l4t-base"],
  "dependencies": {
    "luciole-humble-dev":           ["luciole-base"],
    "luciole-humble-cuda-dev":      ["luciole-cuda-base"],
    "luciole-humble-cuda-runtime":  ["luciole-cuda-base"],
    "luciole-humble-l4t-dev":       ["luciole-l4t-base"],
    "luciole-humble-l4t-runtime":   ["luciole-l4t-base"]
  },
  "arch_overrides": {
    "luciole-base":                  ["amd64"],
    "luciole-cuda-base":             ["amd64"],
    "luciole-humble-dev":            ["amd64"],
    "luciole-humble-cuda-dev":       ["amd64"],
    "luciole-humble-cuda-runtime":   ["amd64"],
    "luciole-l4t-base":             ["arm64"],
    "luciole-humble-l4t-dev":       ["arm64"],
    "luciole-humble-l4t-runtime":   ["arm64"]
  }
}
```

## Local Build

Run from the image directory:

```bash
cd src/<image-name>
docker compose build          # using docker-compose.yml (context is repo root)
# or directly from repo root
docker build -f src/<image-name>/Dockerfile -t <image-name> .
```

## CI/CD Behavior

- **Trigger**: push to `main` (changes under `src/**` or `.github/workflows/publish-images.yml`), or manual `workflow_dispatch` (builds all images).
- **Change detection**: reads `image-deps.json`. If `src/_scripts/**` or `src/_assets/**` changed → rebuilds ALL images. If a base image changed → rebuilds that base + all its dependent final images. If a final image changed → rebuilds that final only. `workflow_dispatch` builds everything.
- **Multi-arch**: `amd64` (`ubuntu-24.04`) and `arm64` (`ubuntu-24.04-arm` native runner, **no QEMU**) are built separately, pushed by digest, then merged into a single multi-arch manifest. `arch_overrides` limits certain images to arm64 only.
- **Two-tier CI jobs**:
  1. `detect-changes` — computes tier1 and tier2 build matrices
  2. `build-push-tier1` — builds base images (skipped if no base changes)
  3. `merge-tier1` — merges multi-arch manifests for base images
  4. `build-push-tier2` — builds final images (runs after merge-tier1, or if tier1 was skipped)
  5. `merge-tier2` — merges multi-arch manifests for final images
- **Image tags**: `latest` (main branch), `main`, `sha-<git-sha>`.
- **Registry**: `ghcr.io/dkuav/<image-name>`, authenticated via `GITHUB_TOKEN` — no extra secrets required.

## Adding a New Image

1. Decide tier: Tier 1 (new base) or Tier 2 (new final that builds on an existing base).
2. Create a new directory under `src/` following the pattern `<project>-<purpose>` (lowercase, hyphen-separated).
3. Add `Dockerfile` (required), `docker-compose.yml` (recommended), `README.md` and `README_zh.md` (both recommended).
4. Update `src/image-deps.json`: add the image to `base_images` (Tier 1) or `dependencies` (Tier 2), and `arch_overrides` if not building all architectures.
5. CI will automatically detect and build the directory on the next push.

## Notes

- Dockerfiles use Aliyun apt mirrors; pip is also configured to use Aliyun PyPI mirrors.
- Default timezone is `Asia/Shanghai`; override via `ARG TZ`.
- `devshell.sh` installs user-home dotfiles (oh-my-zsh, neovim, nvm). It **must** run as the target user (`USER ${USERNAME}` before the `RUN` step in the Dockerfile), followed by `USER root` for cleanup.
- neovim is installed from a binary tarball; when adding an arm64-compatible script update, select the correct arch binary (`nvim-linux-x86_64` vs `nvim-linux-arm64`).
- Each image directory should include both `README.md` (English) and `README_zh.md` (Chinese). The two files must cross-link to each other.

## Documentation Sync

**After modifying any file in an image directory, always check and update the corresponding documentation.**

| Changed file | Documentation to update |
|---|---|
| `Dockerfile` | `README.md` and `README_zh.md` — update affected sections (tools list, build args, notes, etc.) |
| `docker-compose.yml` | `README.md` and `README_zh.md` — update Quick Start / 快速开始 examples |
| `src/_scripts/*.sh` | Update any image READMEs that reference the affected script's features |
| `README.md` | Keep `README_zh.md` in sync (same structure and content, Chinese translation) |
| `README_zh.md` | Keep `README.md` in sync (same structure and content, English) |

Both `README.md` and `README_zh.md` must always reflect the current state of `Dockerfile` and `docker-compose.yml`.

