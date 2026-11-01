# DKUAV Images — Agent Instructions

## Build contracts

- Images are published as `ghcr.io/dkuav/<directory-name>`. Keep lowercase hyphenated names.
- `src/<image>/image.yml` is the source of truth for build configuration, platforms, base dependencies, copied inputs and smoke policy. There is no central dependency map or handwritten image matrix.
- YAML declares configuration; Dockerfiles declare installation order; `src/_scripts` implements capabilities; `tools/images` validates and plans builds and emits Buildx Bake graphs.
- Each manifest describes one published image. Preserve the existing image names and the main/latest/seven-character SHA/version tag conventions.
- All Dockerfiles use the repository root as build context. Compose uses `context: ../..`.
- Internal bases use `base.dependency` and same-checkout Bake named contexts. The planner adds build ancestors without selecting them for publication. Child platforms must be supported by their parent.
- External bases need an explicit version tag and an explicit digest value or null. CUDA uses `nvcr.io/nvidia/pytorch:26.06-py3`; Ascend uses `ascendai/torch-npu:2.14.0-cann9.2.0-910b-ubuntu22.04-py3.12` with a null digest.
- `BASE_IMAGE` is injected by the build tool. Direct Docker/Compose builds retain Dockerfile defaults and final-image `BASE_TAG` compatibility; these use the published base by default.

## Shared scripts and Dockerfiles

- Copy each independently changeable shared file explicitly and declare it in manifest `inputs`. Keep capability `COPY + RUN` pairs adjacent; do not copy entire script/asset directories.
- Keep common Python development tools in `src/_assets/python-dev-requirements.txt`. CUDA and Ascend consume that file through separate pip installers because CUDA extras and Ascend vendor constraints differ.
- Preserve capability order in CUDA base: system, dev-tools, WSLg, pip, CMake, networking libraries, user and SSH. Python is supplied by NVIDIA. Ascend is a separate ARM64 image built from the vendor TorchNPU base; preserve vendor Python and CANN.
- `opencv.sh` is currently disabled. Do not claim the NVIDIA OpenCV installation is quarantined or promise a particular apt OpenCV version without verifying a built image.
- ROS 2 is added in both final images. LLVM, devshell and cached pre-commit hooks are dev-only.
- Run devshell/precommit as the target user, then return to root for mirror configuration and cleanup. Select correct binaries for amd64/arm64.
- Run `finalize-mirror.sh` as root after all apt/pip installation. CUDA dev/runtime select Aliyun; Ascend selects upstream.
- CUDA base defaults to root. Final Dockerfiles set `USER luciole`; the shared entrypoint starts sshd according to `SSH_MODE` then execs the command. The account starts locked, password mode is the default, and root SSH login is disabled. APP_USER is CUDA metadata, not privilege control.
- Do not change software versions, SSH policy or existing smoke assertions merely to make a build refactor pass.

## CI and verification

- Run `python -m pip install -e '.[dev]'`, `python -m tools.images validate`, `python -m ruff check tools`, `python -m ruff format --check tools`, and `python -m pytest` after changing build tooling or contracts.
- Build/test affected images on native amd64 and arm64. No QEMU. Use `plan --image <name>` or `plan --all`, then `bake --platform <platform> --mode load`, `docker buildx bake`, and `test` as documented in the root README.
- Plan changes through actual copied inputs and smoke dependencies, then propagate to downstream consumers. README and Compose changes do not trigger image builds; tooling/schema/workflow changes do.
- PR jobs have contents:read only, never log in to GHCR, and never push images or caches. Publishing jobs have contents:read and packages:write.
- The reusable native workflow builds, loads and tests a same-commit graph before pushing selected images by digest. All native workers must succeed before merging public manifests.
- Native workers must free unused hosted-runner SDKs and preloaded Docker images before creating Buildx, retain host Python/Node/Docker, limit BuildKit solver parallelism to one, and report disk usage even on failure. Account for both BuildKit cache and locally loaded smoke-test images when changing the graph.
- Every smoke script lives in `src/_tests`, uses `_lib.sh`, and is explicitly declared in the manifest. CUDA base is advisory; CUDA dev/runtime and Ascend are required. Ascend hardware checks are separate and must run on a compatible NPU host. Missing scripts/build/container failures are always fatal. Pass SMOKE_HARD_GATE explicitly.
- Preserve the separate manual linker-diagnostic workflow and historical evidence; existing upstream issues are outside this migration.
- Generated plans, Bake configurations and digest metadata are CI artifacts, not checked-in sources.
- Transfer full Bake metadata through files/stdin, never environment variables or command-line arguments; whole-graph provenance can exceed Linux exec limits. Encode embedded action output with `toJSON` inside a quoted heredoc.

## Documentation sync

- After modifying a Dockerfile, manifest or Compose file, update its image README.md and README_zh.md together. Both must cross-link.
- Shared-script feature changes require updates to all affected image guides.
- Keep the root bilingual READMEs and paired docs synchronized with commands, tag behavior, test policy, tools and defaults.
- Update AGENTS.md when build or maintenance conventions change. Historical diagnostic documents must clearly distinguish past evidence from current guarantees.
