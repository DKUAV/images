# DKUAV Images — Agent Instructions

## Build contracts

- Images are published as `ghcr.io/dkuav/<YAML-name>`. Keep lowercase hyphenated names.
- `src/<image>/image.yml` is the source of truth for build configuration, platforms, base dependencies, copied inputs and smoke policy. There is no central dependency map or handwritten image matrix.
- YAML declares configuration; Dockerfiles declare installation order; `vendor/image-kit/scripts` implements shared capabilities and `src/_scripts` supplies Luciole extensions; `image-kit` validates and plans builds and emits Buildx Bake graphs; `tools/` retains consumer policy checks and compatibility imports.
- Initialize the commit-pinned public `vendor/image-kit` submodule with `git submodule update --init --recursive` before validation/builds. Shared capabilities and assets belong to the component; Luciole extensions remain local. Use image-kit 0.2 schema/plan v2 and one shared CLI. YAML names are unique publication/dependency identifiers and need not match directory names. Keep account, Dockerfile and documentation checks in `tools/check_repository.py`. Publish component changes before committing a consumer pin update. CI must not follow a moving component branch.
- Group component scripts under `system`, `dev`, `python`, `libraries`, and `integrations`; prefix platform-specific scripts with their platform name.
- Each manifest declares a published name and explicit variants. Preserve package names; publish variant channels, `<variant>-<sha12>-<run-id>-<attempt>` build tags and receipt-promoted `<variant>-vMAJOR.MINOR.PATCH` releases. Do not maintain old global aliases or delete historical tags.
- All Dockerfiles use the repository root as build context. CUDA Compose builds use `context: ../..`; Ascend Compose only runs published images, with builds handled by manifest/Bake.
- Internal bases use `base.target` and `base.context` and same-checkout Bake named contexts. The planner adds build ancestors without selecting them for publication. Child platforms must be supported by their parent.
- External bases need an explicit version tag and an explicit digest value or null. CUDA uses `nvcr.io/nvidia/pytorch:26.06-py3`; Ascend uses `ascendai/torch-npu:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12` with a null digest.
- `BASE_IMAGE` is injected by the build tool. Direct Docker/Compose builds retain Dockerfile defaults and final-image `BASE_TAG` compatibility; these use the published base by default.

## Shared scripts and Dockerfiles

- Copy each independently changeable shared file explicitly and declare it in manifest `inputs`. Keep capability `COPY + RUN` pairs adjacent; do not copy entire script/asset directories.
- Keep common Python development tools in `vendor/image-kit/assets/python-dev-requirements.txt`. CUDA and Ascend consume that file through separate pip installers because CUDA extras and Ascend vendor constraints differ.
- Preserve capability order in CUDA base: system, dev-tools, WSLg, pip, CMake, networking libraries, user and SSH. Python is supplied by NVIDIA. Ascend is a separate ARM64 image built from the vendor TorchNPU base; preserve vendor Python and CANN.
- `opencv.sh` is currently disabled. Do not claim the NVIDIA OpenCV installation is quarantined or promise a particular apt OpenCV version without verifying a built image.
- ROS 2 is added in both final images. LLVM, devshell and cached pre-commit hooks are dev-only.
- Run devshell/precommit as the target user, then return to root for mirror configuration and cleanup. Select correct binaries for amd64/arm64.
- Run `finalize-mirror.sh` as root after all apt/pip installation. CUDA dev/runtime select Aliyun; Ascend selects upstream.
- CUDA base and Ascend default to root. CUDA final Dockerfiles set `USER luciole`; the shared entrypoint starts sshd according to `SSH_MODE` then execs the command. Managed non-root accounts start locked. CUDA defaults to password SSH; Ascend defaults to key-only SSH with nonempty authorized keys. CUDA final images prohibit root SSH by default; Ascend explicitly selects root. Root password mode requires a mounted password file and key-only mode requires nonempty authorized keys unless `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` explicitly allows starting sshd while waiting for keys. APP_USER is CUDA metadata, not privilege control.
- Do not change software versions, SSH policy or existing smoke assertions merely to make a build refactor pass.

## CI and verification

- Use Ruff with an 88-character line length and double quotes. Preserve the Python 3.11 target and the existing lint rules; use ty with its default configuration.
- Use `uv run --no-sync pre-commit install` to enable repository hooks and `uv run --no-sync pre-commit run --all-files` to check all tracked files. Ruff and ty hooks use the locked dev environment. Consumer hooks skip `vendor/`; run the component hooks separately.

- Keep `uv.lock` synchronized with project and local component dependencies. CI uses `uv sync --locked`; never use a moving component branch or bypass stale lockfiles.

- Run `uv sync --locked --extra dev`, activate `.venv`, then run `python -m tools.check_repository`, `python -m tools.images validate`, `python -m ruff check tools`, `python -m ruff format --check tools`, `python -m pytest`, and `python -m pytest vendor/image-kit/tests` after changing build tooling or contracts.
- Build/test affected images on native amd64 and arm64. No QEMU. Use `plan --target <name>/<variant>` or `plan --all`, then `bake --platform <platform> --mode load`, `docker buildx bake`, and `test` as documented in the root README.
- Component pin (`vendor/image-kit`) and `.gitmodules` changes rebuild all images; every checkout that validates manifests or builds images initializes submodules recursively.
- Plan changes through actual copied inputs and smoke dependencies, then propagate to downstream consumers. README and Compose changes do not trigger image builds; tooling/schema/workflow changes do.
- PR jobs have contents:read only, never log in to GHCR, and never push images or caches. Publishing jobs have contents:read and packages:write.
- The reusable native workflow builds, loads and tests a same-commit graph before pushing selected images by digest. All native workers must succeed before merging public manifests.
- Native workers must free unused hosted-runner SDKs and preloaded Docker images before creating Buildx, retain host Python/Node/Docker, limit BuildKit solver parallelism to one, and report disk usage even on failure. Account for both BuildKit cache and locally loaded smoke-test images when changing the graph.
- Every smoke script lives in `src/_tests`, uses `_lib.sh`, and explicitly declares `variants[].tests[].library`, `variants[].tests[].script` and its inputs in the manifest. CUDA base is advisory; CUDA dev/runtime and Ascend are required. Ascend hardware checks are separate and must run on a compatible NPU host. Missing scripts/build/container failures are always fatal. Pass SMOKE_HARD_GATE explicitly.
- Preserve the separate manual linker-diagnostic workflow and historical evidence; existing upstream issues are outside this migration.
- Generated plans, Bake configurations and digest metadata are CI artifacts, not checked-in sources.
- Transfer full Bake metadata through files/stdin, never environment variables or command-line arguments; whole-graph provenance can exceed Linux exec limits. Encode embedded action output with `toJSON` inside a quoted heredoc.

## Documentation sync

- After modifying a Dockerfile, manifest or Compose file, update its image README.md and README_zh.md together. Both must cross-link.
- Shared-script feature changes require updates to all affected image guides.
- Keep root and image `README.md` / `README_zh.md` pairs synchronized and cross-linked. Write all documents under `docs/` in English only; do not require or add translated docs. Keep commands, tag behavior, test policy, tools and defaults accurate in both README languages.
- Update AGENTS.md when build or maintenance conventions change. Historical diagnostic documents must clearly distinguish past evidence from current guarantees.

## Commit message format

- Format commit subjects as `<Type>: <summary>`, where `Type` is one of `Feat`, `BugFix`, `Refactor`, or `Doc`.
- Separate the subject from the body with a blank line.
- Describe changes in the body as a numbered list.

```text
Refactor: Synchronize shared installers and SSH behavior

1. Align shared scripts and pass installation options explicitly.
2. Update related configuration, bilingual documentation and tests.
```

## Unified v2 publication

Use one worker per dependency component and native platform, pass `--component` to worker
commands and qualify artifacts with `worker_id` and run attempt. Keep the full plan for merge.
Ascend defaults to root with HOME=/root to read the vendor CANN environment; omit UID/GID/groups
from its manifest. Its Bash smoke override restores the installed environment and explicitly
checks the real entrypoint and credential-gated root SSH. CUDA account policy is unchanged.
Ascend Compose mounts the existing host `SSH_CONFIG_DIR` read-only at `/root/.ssh`; retain
nonempty authorized-key validation and root ownership with directory/file modes 0700/0600.

Use the shared v2 plan and derived native worker matrix. Validate/build/test before digest publication; merge checks all required workers and the full identity before updating tags. Formal versions promote a verified main receipt without rebuilding or creating Git tags. Keep component publication before consumer pin commits. Docs are English-only; README pairs remain bilingual.
