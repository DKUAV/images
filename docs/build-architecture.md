# Build architecture

The pinned image-kit 0.2 package owns the schema v2, repository model, planner, native Bake
renderer, smoke execution and digest publication. YAML `name` controls package identity;
directories only locate manifests and explicitly referenced files. Both Luciole and utils/images
use the same interface. See the shared [manifest reference](../vendor/image-kit/docs/manifest-reference.md),
[CLI contract](../vendor/image-kit/docs/cli-reference.md) and
[migration](../vendor/image-kit/docs/migration-v2.md).

Dockerfiles retain installation order and direct-build defaults. Manifests own software choices,
platforms, build arguments, internal bases, inputs and test contracts. Consumer checks retain
account inheritance, Dockerfile ARG/COPY wiring and bilingual README rules. Documents in `docs/`
are English-only. Generated plans, Bake files and publication receipts are CI artifacts.

## Selection and native execution

`plan --all`, `--family <YAML-name>` or `--target <name/variant>` select outputs. Git-based planning
uses actual manifest, Dockerfile, installation and smoke inputs and propagates to downstream
consumers. README and Compose changes alone do not rebuild images. Infrastructure and component
pin changes rebuild all targets. Explicit Git diffs retain deleted and renamed input paths.

Ancestors are added without expanding publication selection and build only on required native
platforms. A parent may cover more platforms than its child. Internal `base.target` and
`base.context` connect to the same checkout via Bake named contexts. The plan derives workers
for amd64 and arm64; no QEMU is configured. `build-test` validates the generated Bake graph,
builds and tests independent components, then reports aggregate failures.

Hosted workers remove unused SDKs and preloaded Docker images before creating Buildx, retain
Python/Node/Docker, limit BuildKit solver parallelism to one, and report disk usage on failure.
Capacity must cover both build cache and locally loaded smoke images. Load graphs import
architecture-scoped Actions caches only; trusted publication can export them. Direct shell
builds expose the Actions cache runtime through the pinned helper action.

Luciole tests explicitly retain the image entrypoint/user and source their declared helper.
utils tests explicitly override the entrypoint with Bash. Both use read-only test mounts,
disable image pulls, and receive `SMOKE_HARD_GATE`. Advisory suppression belongs to the helper;
container startup, missing scripts and Docker errors remain fatal. Hardware checks are separate.

## Publication and formal releases

PRs have read-only contents access and never log in, push images or export caches. Main and
manual publications first complete validation and native smoke tests, push selected targets
by digest, and collect file-loaded Bake metadata. Full provenance is transferred through
`toJSON` inside a quoted Node heredoc, never an environment variable or command argument.
Build ID is `<run-id>-<attempt>` and is passed unchanged through every pipeline stage.

The merge job waits for every native worker. It verifies the exact expected platform set and
shared build identity, composes indexes with provenance, and checks all existing build tags
before writing public tags. Build tags are `<variant>-<sha12>-<run-id>-<attempt>` and are never
overwritten with different content. Only after all build tags succeed does main advance the
floating `<variant>` channels. Other refs receive build tags only. No global `latest`, `main`,
bare SHA or unprefixed version tag is generated; historical artifacts remain available.

Merge emits `publication.json` with source identity, platforms and final index digests. The
separate release workflow selects a successful main publication run and attempt, validates its
receipt and creates `<variant>-vMAJOR.MINOR.PATCH` from existing digests without rebuilding.
Artifacts are attempt-qualified and receipts retained for 90 days. Registry writes across tags
are sequential, not transactional; failures stop later promotion. Keep a digest for fixed use.
Native image builds and NPU tests remain distinct from static tooling checks.
