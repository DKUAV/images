# DKUAV Images — Agent Instructions

This repository manages Docker images for the DKUAV project. Images are published to GitHub Container Registry (`ghcr.io/dkuav/<image>`).

## Repository Layout

```
src/
  _scripts/               # Shared installation scripts
  _assets/                # Shared assets (e.g. pre-commit config)
  _tests/                 # Smoke tests run after CI merge (smoke-<image>.sh + _lib.sh)
  image-deps.json         # CI dependency + arch-override map
  <image-name>/           # One subdirectory per image
    Dockerfile            # Required (CI uses this to detect image directories)
    docker-compose.yml    # Optional, for local build/run
    README.md             # Optional, image documentation
    README_zh.md          # Optional, image documentation (Chinese)
.github/workflows/
  publish-images.yml      # CI: detect changes → multi-arch build → merge manifest → smoke test
```

## Image Naming Convention

`src/<image-name>` → `ghcr.io/dkuav/<image-name>`

- Directory name becomes the image name. **Do not** use uppercase letters or spaces.
- Example: `src/luciole-cuda-dev` → `ghcr.io/dkuav/luciole-cuda-dev`

## Build Context

All Dockerfiles use the **repository root** (`.`) as the Docker build context so that `COPY src/_scripts/` works. `docker-compose.yml` files therefore set `context: ../..` and `dockerfile: src/<image-name>/Dockerfile`.

## Shared Scripts (`src/_scripts/`)

Numbered shell scripts that encapsulate all reusable installation logic:

| Script | Purpose | Used by |
|--------|---------|---------|
| `system.sh` | Apt upgrade, timezone, locale — minimal system bootstrap | All base images |
| `dev-tools.sh` | Developer CLI toolset (editors, VCS, build, debug, ffmpeg) — run right after `system.sh` | All base images |
| `wslg.sh` | GUI / WSLg deps (D-Bus, CJK fonts, Mesa, PulseAudio) — run after `dev-tools.sh` | All base images |
| `python-install.sh` | Python 3.10 from apt + pip bootstrap | Currently unused (pytorch:24.10-py3 already ships Python); kept for future CPU-only bases |
| `pip-packages.sh` | pip packages, uv | All base images |
| `opencv.sh` | Replace NVIDIA's incomplete OpenCV 4.7.0 (no FFMPEG / GStreamer) with apt's `libopencv-dev` 4.5.4; quarantine the original under `/usr/local/lib/nvidia-opencv-4.7.0.disabled/` | `luciole-cuda-base` |
| `ros2.sh` | ROS 2 (reads `$ROS_DISTRO`, `$ROS_TARGET`) | All final images |
| `cmake.sh` | Newer CMake binary release (reads `$CMAKE_VERSION`) | `luciole-cuda-base` (inherited by every Tier 2 final) |
| `clang.sh` | LLVM 21 (clang-format, clang-tidy, lldb) | Dev final images only |
| `user.sh` | Non-root user + sudo (reads `$USERNAME`, `$USER_UID`) | All base images |
| `devshell.sh` | zsh, oh-my-zsh, neovim, starship, nvm, … | Dev final images only — **must run as target user** |
| `precommit.sh` | Pre-cache pre-commit hook environments from `_assets/.pre-commit-config.yaml` | Dev final images only — **must run as target user** |
| `finalize-mirror.sh` | As the **final step**, rewrite apt + pip sources to Aliyun mirrors so users in China get fast installs post-pull. Build itself still uses upstream sources. **Must run as root, after every apt/pip install is finished.** | All Tier 2 final images |

Each Dockerfile does `COPY src/_scripts/ /tmp/scripts/ && chmod +x /tmp/scripts/*.sh`, runs the required scripts, then `RUN rm -rf /tmp/scripts`. Dev images also `COPY src/_assets/ /tmp/assets/` for `precommit.sh`.

## Two-Tier Image Architecture

### Tier 1 — Base Images (published to GHCR, used as FROM in Tier 2)

| Directory | Base FROM | Description |
|-----------|-----------|-------------|
| `src/luciole-cuda-base` | `nvcr.io/nvidia/pytorch:24.10-py3` | PyTorch/CUDA + pip packages + user (amd64, arm64) |

### Tier 2 — Final Images (depend on Tier 1 base images)

| Directory | FROM (Tier 1) | Arch | Description |
|-----------|---------------|------|-------------|
| `src/luciole-cuda-dev` | `luciole-cuda-base` | amd64, arm64 | CUDA dev: ROS 2 + devtools + devshell |
| `src/luciole-cuda-runtime` | `luciole-cuda-base` | amd64, arm64 | CUDA runtime: ROS 2 + cmake only |

## `src/image-deps.json`

Drives CI change detection and dependency propagation:

```json
{
  "base_images": ["luciole-cuda-base"],
  "dependencies": {
    "luciole-cuda-dev":      ["luciole-cuda-base"],
    "luciole-cuda-runtime":  ["luciole-cuda-base"]
  },
  "arch_overrides": {
    "luciole-cuda-base":     ["amd64", "arm64"],
    "luciole-cuda-dev":      ["amd64", "arm64"],
    "luciole-cuda-runtime":  ["amd64", "arm64"]
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
  1. `detect-changes` — computes tier1, tier2, and smoke-test matrices
  2. `build-push-tier1` — builds base images (skipped if no base changes)
  3. `merge-tier1` — merges multi-arch manifests for base images
  4. `build-push-tier2` — builds final images (runs after merge-tier1, or if tier1 was skipped)
  5. `merge-tier2` — merges multi-arch manifests for final images
  6. `smoke-test` — pulls each built image at its `sha-<git-sha>` tag on a **native arch runner** and runs `src/_tests/smoke-<image>.sh`; any assertion failure fails the whole pipeline
- **Smoke tests (gate)**: `src/_tests/smoke-<image>.sh` is the per-image contract check (OpenCV `find_package` resolves to apt, `ros2` installable, dev shell tools present, mirror applied in Tier 2, etc.). Shared helpers live in `src/_tests/_lib.sh`. The job runs only for images that were *actually built* this run (skipped when nothing changed). It is a **hard gate**: a failed smoke test marks the workflow failed.
  - To smoke-test locally: `docker run --rm -v "$PWD/src/_tests:/tmp/smoke:ro" <image> bash -lc '. /tmp/smoke/_lib.sh; source /tmp/smoke/smoke-<image>.sh'`
- **Image tags**: `latest` (main branch), `main`, `sha-<git-sha>`.
- **Registry**: `ghcr.io/dkuav/<image-name>`, authenticated via `GITHUB_TOKEN` — no extra secrets required.

## Adding a New Image

1. Decide tier: Tier 1 (new base) or Tier 2 (new final that builds on an existing base).
2. Create a new directory under `src/` following the pattern `<project>-<purpose>` (lowercase, hyphen-separated).
3. Add `Dockerfile` (required), `docker-compose.yml` (recommended), `README.md` and `README_zh.md` (both recommended).
4. Update `src/image-deps.json`: add the image to `base_images` (Tier 1) or `dependencies` (Tier 2), and `arch_overrides` if not building all architectures.
5. CI will automatically detect and build the directory on the next push.

## Notes

- **Mirrors strategy**: during the build every script (`system.sh`, `ros2.sh`, `pip-packages.sh`, …) uses the upstream Ubuntu / PyPI sources, because GitHub Actions runners are usually closer to those than to Chinese mirrors. `finalize-mirror.sh` then flips the *persisted* apt + pip sources to Aliyun **as the very last step** of each Tier 2 final image, so end users in China get fast `apt` / `pip` out of the box without that mirror ever slowing down a build.
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

