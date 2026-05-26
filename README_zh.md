# DKUAV Images

DKUAV 项目的 Docker 镜像管理仓库。镜像通过 GitHub Actions 自动构建并发布至 GitHub Container Registry（`ghcr.io/dkuav/<image>`）。

> For English documentation, see [README.md](README.md)

## 镜像架构

本仓库采用**两级镜像层级**，在 3 个 OS 家族（Ubuntu、CUDA/PyTorch、L4T）之间最大化复用镜像层：

```mermaid
graph TD
  U["mcr.microsoft.com/devcontainers/base:ubuntu22.04"] --> LB["ghcr.io/dkuav/luciole-base\n(system + Python + pip + user)\namd64 only"]
  C["nvcr.io/nvidia/pytorch:24.10-py3\n(已含 Python + PyTorch + CUDA)"] --> CB["ghcr.io/dkuav/luciole-cuda-base\n(system + pip + user)\namd64 only"]
  L["nvcr.io/nvidia/l4t-tensorrt:r10.3.0-devel\n(已含 Python + TensorRT, arm64)"] --> LTB["ghcr.io/dkuav/luciole-l4t-base\n(system + pip + user)\narm64 only"]

  LB --> HD["luciole-humble-dev\n(ROS 2 + cmake + clang + .NET + devshell)\namd64 only"]
  CB --> HCD["luciole-humble-cuda-dev\n(ROS 2 + cmake + clang + .NET + devshell)\namd64 only"]
  CB --> HCR["luciole-humble-cuda-runtime\n(ROS 2 + cmake)\namd64 only"]
  LTB --> HLD["luciole-humble-l4t-dev\n(ROS 2 + cmake + clang + .NET + devshell)\narm64 only"]
  LTB --> HLR["luciole-humble-l4t-runtime\n(ROS 2 + cmake)\narm64 only"]
```

### 第一层 — 基础镜像

发布至 GHCR，供第二层 Dockerfile 作为 `FROM` 使用。

| 镜像 | 基础 FROM | 架构 | 描述 |
|------|-----------|------|------|
| [`luciole-base`](src/luciole-base/) | `mcr.microsoft.com/devcontainers/base:ubuntu22.04` | 仅 amd64 | Ubuntu 22.04 + Python 3.10 + pip 包 + 用户 |
| [`luciole-cuda-base`](src/luciole-cuda-base/) | `nvcr.io/nvidia/pytorch:24.10-py3` | 仅 amd64 | PyTorch/CUDA + pip 包 + 用户 |
| [`luciole-l4t-base`](src/luciole-l4t-base/) | `nvcr.io/nvidia/l4t-tensorrt:r10.3.0-devel` | 仅 arm64 | L4T TensorRT + pip 包 + 用户 |

### 第二层 — 最终镜像

| 镜像 | 基础 | 架构 | 包含内容 |
|------|------|------|---------|
| [`luciole-humble-dev`](src/luciole-humble-dev/README_zh.md) | `luciole-base` | 仅 amd64 | ROS 2 Humble · cmake · clang · .NET · devshell |
| [`luciole-humble-cuda-dev`](src/luciole-humble-cuda-dev/) | `luciole-cuda-base` | 仅 amd64 | ROS 2 Humble · cmake · clang · .NET · devshell |
| [`luciole-humble-cuda-runtime`](src/luciole-humble-cuda-runtime/) | `luciole-cuda-base` | 仅 amd64 | ROS 2 Humble · cmake |
| [`luciole-humble-l4t-dev`](src/luciole-humble-l4t-dev/) | `luciole-l4t-base` | 仅 arm64 | ROS 2 Humble · cmake · clang · .NET · devshell |
| [`luciole-humble-l4t-runtime`](src/luciole-humble-l4t-runtime/) | `luciole-l4t-base` | 仅 arm64 | ROS 2 Humble · cmake |

**devshell** 包含：zsh · oh-my-zsh · neovim（NvChad）· starship · nvm · bat · fzf · eza · zoxide

## 使用镜像

```bash
docker pull ghcr.io/dkuav/<image-name>:latest
```

## 本地构建

所有 Dockerfile 均以**仓库根目录**为 build context。在**镜像目录**下运行：

```bash
cd src/<image-name>
docker compose build
```

或从仓库根目录直接构建：

```bash
docker build -f src/<image-name>/Dockerfile -t <image-name> .
```

## 添加新镜像

1. 确定层级：第一层（新基础镜像）或第二层（依赖已有基础镜像）。
2. 在 `src/<image-name>/` 下创建 `Dockerfile`（必须）、`docker-compose.yml`、`README.md` 和 `README_zh.md`。
3. 更新 [`src/image-deps.json`](src/image-deps.json) — 加入 `base_images` 或 `dependencies`，如有架构限制则加入 `arch_overrides`。
4. Push 到 `main`，CI 自动检测变更并构建发布。

详见 [AGENTS.md](AGENTS.md) 了解完整的 CI/CD 行为、命名约定和共享脚本说明。

## CI/CD

```mermaid
graph LR
  A[detect-changes] --> B["build-push-tier1\n（基础镜像 matrix）"]
  B --> C["merge-tier1\n（合并 multi-arch manifest）"]
  C --> D["build-push-tier2\n（最终镜像 matrix）"]
  D --> E[merge-tier2]
  A -. "仅 tier2 变更" .-> D
```

- **变更检测**（读取 `src/image-deps.json`）：
  - `src/_scripts/**` 有变更 → 重建**全部**镜像
  - 基础镜像有变更 → 重建该基础镜像**及**所有依赖它的最终镜像
  - 最终镜像有变更 → 只重建该最终镜像
  - `workflow_dispatch` → 构建全部镜像
- **多架构**：amd64（`ubuntu-24.04`）和 arm64（`ubuntu-24.04-arm` 原生 Runner，无 QEMU）分别构建，按 digest 推送后合并为 multi-arch manifest。`image-deps.json` 中的 `arch_overrides` 可限制镜像仅在特定架构构建。
- **标签**：`latest`、`main`、`sha-<git-sha>`。
- **认证**：仅需 `GITHUB_TOKEN`，无需额外 secrets。

工作流定义：[`.github/workflows/publish-images.yml`](.github/workflows/publish-images.yml)
