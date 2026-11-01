# Build architecture

> 中文文档：[build-architecture_zh.md](build-architecture_zh.md)

## Responsibilities

Each existing image directory has one `image.yml`; its name remains the GHCR repository name. The manifest declares the base, platforms, build arguments, copied shared inputs and smoke contract. Dockerfiles own installation order and user transitions. Library versions, ROS options and pre-commit configuration are passed explicitly through named script arguments. System timezone and upgrade policy are also passed explicitly. Shared capabilities and assets come from the pinned image-kit submodule; Luciole extensions remain local.

Python 3.11+ tooling validates these contracts and produces a versioned JSON build plan and a Buildx Bake graph. The checked-in [schema](../schemas/image.schema.json) and [manifest reference](manifest-reference.md) define the contract. Generated JSON is ignored locally and uploaded as CI artifacts.

The Dockerfiles retain defaults for direct Docker/Compose builds. YAML is authoritative for the standard tool/CI path; update the compatibility defaults and bilingual guides when changing manifest defaults. Direct final-image builds use a published base unless explicitly overridden.

## Selection and dependencies

`plan --all` selects every image. `plan --image <name>` selects just that image for publication. `plan --base <commit> --head <commit>` selects consumers of changed manifests, Dockerfiles, shared inputs and smoke inputs, then recursively selects their downstream consumers. Git diffs disable rename collapsing so removal of an old input path is visible.

The planner then adds every ancestor needed to build the selection. These additional targets have `publish: false`; selecting dev alone therefore builds/tests base and dev, without releasing base or runtime. `base.dependency` becomes a Bake named context referencing `target:<base-name>`, so dev uses the base built from the same checkout, including in PRs.

README and Compose changes do not select images. Changes to the image tooling, schemas, workflows, Python project configuration or Docker context exclusions select all images. Changes to a shared smoke helper affect all its declared consumers. A missing declared file fails validation instead of silently skipping its consumer.

## Native builds and smoke tests

The runner matrix is derived from the plan: `linux/amd64` uses `ubuntu-24.04`; `linux/arm64` uses `ubuntu-24.04-arm`. Each worker renders only its native platform. QEMU is not configured.

Each worker builds the entire selected dependency graph and loads its images for smoke tests. Before creating Buildx, the native workflow removes unused hosted-runner SDKs (Android, .NET, Haskell, Swift, Boost and CodeQL), clears apt downloads and prunes preloaded Docker images. Python, Node, Docker and checkout inputs are retained. BuildKit solver parallelism is limited to one to reduce concurrent installation work in the dev/runtime branches. Disk usage is logged before/after cleanup and at job completion, including failures. Capacity must cover the NVIDIA layers, BuildKit cache and loaded test images; larger graphs or upstream images may still require a larger native runner.

Load mode exports local images at `ghcr.io/<owner>/<name>:sha-<7-character-sha>`. The test command mounts `src/_tests` read-only at `/tmp/smoke`, sources `_lib.sh`, runs the declared script and passes `SMOKE_HARD_GATE` explicitly. It tests dependency-only targets as well as publish targets, preserving the image entrypoint and Dockerfile user.

Base uses advisory assertions; dev/runtime require success. Advisory handling stays in the shell helper, so a Docker failure or a missing script still fails the worker. The test runner attempts all loaded contracts before returning an aggregate failure. Build failures and dependency failures remain fatal.

The base preserves upstream package sources. Dev/runtime run `finalize-mirror.sh` as root after all package installation, then clean up and refresh `ldconfig`. Devshell and pre-commit initialization run as the target non-root user.

## Release and permissions

PR callers grant only `contents: read`. They build/load/test without GHCR login, image pushes or cache exports. Publishing callers grant `contents: read` and `packages: write`. Both call the same native workflow, and their Bake graphs differ only in cache/export behavior.

CI uses `--github-cache` with `docker/bake-action`, which provides GitHub cache authentication. Cache scopes include image and architecture. Load graphs only import caches; publishing graphs may export them. Local graphs omit GitHub cache settings by default and need no Actions credentials.

After native smoke tests, publish mode exports selected targets by digest; build-only ancestors remain cache-only. Workers collect the actual Bake digest metadata. Merge validates the complete expected image/platform set, revision, owner and digest format before any tag update. If any worker fails, merge is skipped. One worker may have uploaded untagged digests, but public tags are not advanced.

Publication metadata, including provenance for the entire graph, is written to a file through Node's standard input before digest collection. The workflow uses `toJSON` to encode the action output as a JavaScript string literal inside a quoted heredoc. Do not put the full metadata in an environment variable or command-line argument: it can exceed Linux process-start limits.

All SHA manifests are created before convenience tags advance. Main publishes `main`, `latest` and `sha-<7-character-sha>`; `v*` events build all images and publish the version and SHA tags. Manual dispatch selects one/all images; other branches receive SHA tags only. Publishers share a concurrency group. Registry updates across multiple image tags are sequential, not transactional; a registry error stops remaining updates and fails CI.

SHA tags identify source revisions, but tag-tracking upstream bases can change across repeated builds. This migration retains the existing tag behavior rather than introducing immutable-tag enforcement. Pin the resulting digest when needed.

## Maintenance and known issues

Add each copied file to `inputs` and give independent scripts adjacent `COPY + RUN` pairs. Validation checks local file copies against the declared inputs and rejects directory-wide copies. Keep the target user's `USERNAME` consistent across internal base relationships.

The OpenCV replacement script remains disabled. Existing OpenCV and PyTorch assertions are preserved; failures remain diagnostics or gates according to the image policy. The [OpenCV analysis](opencv-status.md) and [linker notes](ld-cache-notes.md) retain historical evidence, not a guarantee about current upstream releases. The separate manual diagnostic workflow is retained.
