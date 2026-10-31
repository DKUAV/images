# 构建架构

> English documentation: [build-architecture.md](build-architecture.md)

## 职责

每个现有镜像目录包含一份 `image.yml`，名称继续对应 GHCR 镜像仓库名。清单声明基础镜像、平台、构建参数、复制的共享输入和烟测契约；Dockerfile 负责安装顺序与用户切换；共享脚本保留已有环境变量接口。

Python 3.11+ 工具校验契约，生成带版本的 JSON 构建计划和 Buildx Bake 图。已提交的 [schema](../schemas/image.schema.json) 和[清单参考](manifest-reference_zh.md)定义格式。生成 JSON 在本地被忽略，在 CI 中作为产物上传。

Dockerfile 保留直接 Docker/Compose 构建的默认值。标准工具与 CI 以 YAML 为准；修改清单默认值时，同步更新兼容默认值和中英文文档。直接构建最终镜像时，除非显式覆盖，否则使用已发布的 base。

## 选择与依赖

`plan --all` 选择全部镜像；`plan --image <name>` 只选择该镜像发布；`plan --base <commit> --head <commit>` 根据清单、Dockerfile、共享输入和烟测输入的变更选择消费者，再递归选择下游。Git 差异禁用重命名折叠，确保旧输入路径的删除仍可检测。

随后计划补齐构建所需祖先，新增目标标为 `publish: false`。因此仅选择 dev 时会构建和测试 base、dev，但不会发布 base 或 runtime。`base.dependency` 转成引用 `target:<base-name>` 的 Bake 命名 context，保证 dev 使用同一工作区构建的 base，PR 同样如此。

README 和 Compose 变更不选择镜像。镜像工具、schema、工作流、Python 项目配置和 Docker 上下文排除规则的修改选择全部镜像；共享烟测 helper 的修改影响所有声明它的消费者。声明文件缺失会使校验失败，不会静默跳过。

## 原生构建与烟测

Runner 矩阵由计划生成：`linux/amd64` 使用 `ubuntu-24.04`，`linux/arm64` 使用 `ubuntu-24.04-arm`。每个任务只生成本机平台，不配置 QEMU。

Load 模式将镜像导入本地，标签为 `ghcr.io/<owner>/<name>:sha-<7位提交号>`。测试命令将 `src/_tests` 只读挂载到 `/tmp/smoke`，加载 `_lib.sh`，运行声明脚本，并显式设置 `SMOKE_HARD_GATE`。构建依赖目标和发布目标均被测试，保留镜像入口脚本与 Dockerfile 用户。

Base 的断言失败仅报告，dev/runtime 必须通过。Advisory 处理保留在 shell helper 中，因此 Docker 失败或缺失脚本仍导致任务失败。测试工具会尝试所有已加载契约后汇总失败；构建失败和依赖失败始终阻断。

Base 保留上游源。Dev/runtime 在全部软件安装结束后，以 root 运行 `finalize-mirror.sh`，再清理并执行 `ldconfig`。Devshell 和 pre-commit 初始化以目标非 root 用户运行。

## 发布与权限

PR 调用者只有 `contents: read`，仅构建、加载和测试，不登录 GHCR、不推送镜像、不导出缓存。发布调用者具有 `contents: read` 和 `packages: write`。两者调用相同的原生工作流，Bake 图的差异限于缓存和导出行为。

CI 使用 `--github-cache` 和 `docker/bake-action`，由后者提供 GitHub 缓存认证。缓存按镜像和架构隔离；Load 图只读取，发布图可以写入。本地默认不生成 GitHub 缓存设置，无需 Actions 凭据。

原生烟测后，Publish 模式按 digest 导出选中的目标，纯构建祖先仅保留缓存。任务采集实际 Bake 元数据；合并操作在任何标签更新之前，验证完整的镜像/平台集合、提交号、owner 与 digest 格式。任一任务失败则跳过合并；其他任务可能已上传未打标签的 digest，但不会推进公开标签。

先创建全部 SHA manifest，再更新便捷标签。Main 发布 `main`、`latest`、`sha-<7位提交号>`；`v*` 事件全量构建，发布版本和 SHA 标签。手动触发选择一个或全部镜像，其他分支只发布 SHA 标签。发布任务共用并发组。多个标签的仓库更新是顺序操作，不具备事务性；仓库错误会停止后续更新并使 CI 失败。

SHA 标签标识源代码提交，但跟踪上游标签的基础镜像在重复构建时可能变化。本次保留现有标签行为，不新增不可变标签强制规则；需要固定制品时锁定最终 digest。

## 维护与已知问题

每个复制文件都加入 `inputs`，独立脚本使用相邻的 `COPY + RUN`。校验器检查本地文件复制是否已声明，并拒绝整目录复制。内部基础镜像关系中的目标 `USERNAME` 必须一致。

OpenCV 替换脚本继续禁用。已有 OpenCV 和 PyTorch 断言保留，失败按各镜像策略报告或阻断。[OpenCV 分析](opencv-status_zh.md)和[链接器说明](ld-cache-notes_zh.md)保留历史证据，不保证当前上游版本行为；独立手动诊断工作流继续保留。
