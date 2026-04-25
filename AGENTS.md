# DKUAV Images — Agent Instructions

This repository manages Docker images for the DKUAV project. Images are published to GitHub Container Registry (`ghcr.io/dkuav/<image>`).

## Repository Layout

```
src/
  <image-name>/         # One subdirectory per image
    Dockerfile          # Required (CI uses this to detect image directories)
    docker-compose.yml  # Optional, for local build/run
    README.md           # Optional, image documentation
    README_zh.md        # Optional, image documentation (Chinese)
.github/workflows/
  publish-images.yml    # CI: detect changes → multi-arch build → merge manifest
```

## Image Naming Convention

`src/<image-name>` → `ghcr.io/dkuav/<image-name>`

- Directory name becomes the image name. **Do not** use uppercase letters or spaces.
- Example: `src/luciole-humble-dev` → `ghcr.io/dkuav/luciole-humble-dev`

## Local Build

Run inside the image directory:

```bash
cd src/<image-name>
docker compose build          # using docker-compose.yml
# or directly
docker build -t <image-name> .
```

## CI/CD Behavior

- **Trigger**: push to `main` (changes under `src/**` or `.github/workflows/publish-images.yml`), or manual `workflow_dispatch` (builds all images).
- **Change detection**: A Python script diffs git commits and only builds directories that changed; `workflow_dispatch` builds everything.
- **Multi-arch**: `amd64` (`ubuntu-24.04`) and `arm64` (`ubuntu-24.04-arm` native runner, **no QEMU**) are built separately, pushed by digest, then merged into a single multi-arch manifest.
- **Image tags**: `latest` (main branch), `main`, `sha-<git-sha>`.
- **Registry**: `ghcr.io/dkuav/<image-name>`, authenticated via `GITHUB_TOKEN` — no extra secrets required.

## Adding a New Image

1. Create a new directory under `src/` following the pattern `<project>-<purpose>` (lowercase, hyphen-separated).
2. Add `Dockerfile` (required), `docker-compose.yml` (recommended), `README.md` and `README_zh.md` (both recommended — see below).
3. CI will automatically detect and build the directory on the next push.

## Current Images

| Directory | Description |
|-----------|-------------|
| [`src/luciole-humble-dev`](src/luciole-humble-dev/README.md) | Ubuntu 22.04 dev container with ROS 2 Humble (desktop), Python 3.10, clang-format 21, WSLg GUI support, zsh + oh-my-zsh, neovim |

## Notes

- Dockerfiles use Aliyun apt mirrors; pip is also configured to use Aliyun PyPI mirrors.
- `luciole-humble-dev` installs neovim from `nvim-linux-x86_64.tar.gz`. **When adding an arm64 image**, select the correct binary based on architecture (e.g., use `uname -m` or a build ARG).
- Default timezone is `Asia/Shanghai`; override via `ARG TZ`.
- Each image directory should include both `README.md` (English) and `README_zh.md` (Chinese). The two files must cross-link to each other: `README.md` links to `README_zh.md` and vice versa.
