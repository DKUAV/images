# DKUAV Images

DKUAV 项目的 Docker 镜像管理仓库。镜像通过 GitHub Actions 自动构建并发布至 GitHub Container Registry（`ghcr.io/dkuav/<image>`）。

> For English documentation, see [README.md](README.md)

## 当前镜像

| 镜像 | Registry | 描述 |
|------|----------|------|
| [`luciole-humble-dev`](src/luciole-humble-dev/README.md) | `ghcr.io/dkuav/luciole-humble-dev` | Ubuntu 22.04 开发容器，含 ROS 2 Humble、Python 3.10、clang-format 21、WSLg GUI 支持、zsh + oh-my-zsh、neovim |

## 使用镜像

```bash
docker pull ghcr.io/dkuav/<image-name>:latest
```

## 本地构建

```bash
cd src/<image-name>
docker compose build
# 或
docker build -t <image-name> .
```

## 添加新镜像

1. 在 `src/` 下新建目录（全小写，连字符分隔，例如 `src/project-runtime`）。
2. 添加 `Dockerfile`（必须）、`docker-compose.yml`（推荐）、`README.md`（推荐）。
3. Push 到 `main` 后，CI 自动检测变更目录并构建发布。

详见 [AGENTS.md](AGENTS.md) 了解 CI/CD 行为、命名约定和架构注意事项。

## CI/CD

- **多架构**：`amd64` + `arm64`（原生 runner，不用 QEMU），合并为单一 multi-arch manifest。
- **标签**：`latest`、`main`、`sha-<git-sha>`。
- **认证**：仅需 `GITHUB_TOKEN`，无需额外 secrets。

工作流定义：[`.github/workflows/publish-images.yml`](.github/workflows/publish-images.yml)
