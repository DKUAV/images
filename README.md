# DKUAV Images

Docker image management repository for the DKUAV project. Images are automatically built and published to GitHub Container Registry (`ghcr.io/dkuav/<image>`) via GitHub Actions.

> 中文文档请见 [README_zh.md](README_zh.md)

## Available Images

| Image | Registry | Description |
|-------|----------|-------------|
| [`luciole-humble-dev`](src/luciole-humble-dev/README.md) | `ghcr.io/dkuav/luciole-humble-dev` | Ubuntu 22.04 dev container with ROS 2 Humble, Python 3.10, clang-format 21, WSLg GUI support, zsh + oh-my-zsh, neovim |

## Pull an Image

```bash
docker pull ghcr.io/dkuav/<image-name>:latest
```

## Local Build

```bash
cd src/<image-name>
docker compose build
# or
docker build -t <image-name> .
```

## Adding a New Image

1. Create a new directory under `src/` (lowercase, hyphen-separated, e.g. `src/project-runtime`).
2. Add `Dockerfile` (required), `docker-compose.yml` (recommended), `README.md` (recommended).
3. Push to `main` — CI will automatically detect and build the new directory.

See [AGENTS.md](AGENTS.md) for CI/CD behavior, naming conventions, and multi-arch notes.

## CI/CD

- **Multi-arch**: `amd64` + `arm64` (native runners, no QEMU), merged into a single multi-arch manifest.
- **Tags**: `latest`, `main`, `sha-<git-sha>`.
- **Auth**: `GITHUB_TOKEN` only — no extra secrets needed.

Workflow: [`.github/workflows/publish-images.yml`](.github/workflows/publish-images.yml)

