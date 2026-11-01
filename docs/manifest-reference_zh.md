# 镜像清单参考

> English documentation: [manifest-reference.md](manifest-reference.md)

## 契约

每份 `src/<name>/image.yml` 描述一个发布镜像。[Schema v1](../schemas/image.schema.json) 拒绝未知字段。Dockerfile 默认值为直接构建提供兼容，标准 Bake/CI 流程使用清单值。本版本不引入变体矩阵。

| 字段 | 含义 |
| --- | --- |
| `schema_version` | 必须为 `1` |
| `name` | 小写连字符名称，与目录和 GHCR 仓库一致 |
| `description` | 非空镜像描述 |
| `dockerfile` | 相对仓库根目录的 Dockerfile 路径 |
| `context` | 必须为 `.`，即仓库根目录 |
| `platforms` | 非空、不重复的 `linux/amd64` 和/或 `linux/arm64` 列表 |
| `base` | 下述外部基础镜像或内部依赖，二选一 |
| `build_args` | 大写参数名，值为字符串、数字或布尔值；布尔值转成小写字符串 |
| `inputs` | 每个共享 COPY 输入对应的仓库相对文件路径或 glob |
| `smoke.script` | 直接位于 `src/_tests` 下的现有脚本 |
| `smoke.inputs` | 额外文件路径或 glob，必须包含 `src/_tests/_lib.sh` |
| `smoke.policy` | `advisory` 仅报告断言失败；`required` 使其失败退出 |

清单、Dockerfile 和声明的烟测脚本自动参与变更检测。`inputs` 必须匹配现有文件。绝对路径、父级跳转、符号链接越界和本地 COPY 整目录均被拒绝。本地 COPY 使用单行 shell 格式和明确文件；阶段/context 的 `COPY --from=` 不作为仓库输入。Dockerfile 的兼容默认值与 YAML 同步维护。根 README 和每个镜像文档均须有非空 `_zh` 对应文件；`validate` 也检查本地文档链接。

## 基础镜像与参数

外部基础镜像：

```yaml
base:
  image: nvcr.io/nvidia/pytorch:26.06-py3
  digest: null
```

Digest 字段必须显式存在。`null` 跟踪明确版本标签，`sha256:<64位小写十六进制>` 锁定内容。拒绝 `latest`、`master` 和未指定标签的外部基础镜像。迁移时不编造上游 digest。

内部基础镜像：

```yaml
base:
  dependency: luciole-cuda-base
```

目标镜像必须存在，其平台覆盖子镜像平台，且 `USERNAME` 与子镜像一致。拒绝依赖环。Bake 注入 `BASE_IMAGE=internal_base` 和 `contexts.internal_base=target:<dependency>`。`BASE_IMAGE` 与兼容专用的 `BASE_TAG` 为保留参数，不能通过 `build_args` 设置。

Base 清单管理 TZ、CMake/库版本、USERNAME、USER_UID、USER_GID 和 USER_GROUPS（逗号分隔的已有附加组，默认为空）；最终镜像清单管理 ROS_DISTRO、ROS_TARGET 和 USERNAME。修改账户名时同时更新 base 与两个最终镜像。拒绝重复 YAML 键，以及 Dockerfile 未声明的构建参数。Dev/runtime 镜像源和 SSH 行为继续由现有脚本负责，不新增镜像源或 SSH 策略接口。

## 命令与生成格式

先运行 `python -m pip install -e '.[dev]'`，再在根目录执行：

```bash
python -m tools.images validate
python -m tools.images list
python -m tools.images plan --all --output build-plan.json
python -m tools.images plan --image luciole-cuda-dev --output build-plan.json
python -m tools.images plan --base <commit> --head <commit> --output build-plan.json
```

`plan` 输出 `schema_version`、`changed_files`、拓扑排序后的 `targets` 和 `build_matrix.include`。每个目标包含 `name`、`platforms`、`publish`、`reason`（`selected` 或 `dependency`）。消费者以当前清单校验计划，拒绝缺失祖先或过期平台列表。

`bake --plan <file> --owner <owner> --revision <full-sha> --repository <owner/repository> --platform <platform> --mode load|publish --output <file>` 生成原生平台图。Owner 必须指定，源代码仓库默认 `dkuav/images`。仅在已认证的 Actions 执行中添加 `--github-cache`；本地默认不配置远端缓存。Load 模式不写缓存；Publish 模式仅为发布目标生成 digest 推送配置，祖先仅输出缓存。

`test --plan <file> --owner <owner> --revision <full-sha> --platform <platform>` 运行已加载镜像的烟测。测试不添加 GPU 参数，验证容器软件契约，不验证 GPU 硬件访问。CLI 错误非零退出；advisory 仅作用于 `_lib.sh` 处理的断言。

CI 额外使用 `collect --metadata <bake-metadata.json> --output <file>` 并传入 plan/owner/revision/platform，采集需要发布的 digest；`merge --digests <directory> --ref <git-ref>` 配合 plan/owner/revision，先检查产物完整性再创建 manifest。`merge --dry-run` 只打印 Docker 命令数组，不修改仓库。Digest 产物 v1 记录 name、platform、digest、owner 和完整提交号。

生成计划与 Bake 配置仅作为本地文件或 CI 产物。Main 使用已有的七位 SHA 标签、`main`、`latest`；版本事件增加 `v*` 标签，不改成新的 `<family>:<variant>` 标签。移除清单不会删除已发布制品。
