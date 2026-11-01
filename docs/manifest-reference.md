# Image manifest reference

> 中文文档：[manifest-reference_zh.md](manifest-reference_zh.md)

## Contract

One `src/<name>/image.yml` describes one published image. Unknown fields are rejected by [schema version 1](../schemas/image.schema.json). Existing Dockerfile defaults provide compatibility for direct builds; the normal Bake/CI path uses manifest values. There is no variant matrix in this version.

| Field | Meaning |
| --- | --- |
| `schema_version` | Must be `1` |
| `name` | Lowercase hyphenated name matching its directory and GHCR repository |
| `description` | Nonempty image description |
| `dockerfile` | Repository-relative Dockerfile path |
| `context` | Must be `.` (repository root) |
| `platforms` | Nonempty unique list of `linux/amd64` and/or `linux/arm64` |
| `base` | Exactly one external base or internal dependency, as below |
| `build_args` | Uppercase argument names with string, numeric or boolean values; booleans become lowercase strings |
| `inputs` | Repository-relative file paths/globs for every shared COPY input |
| `smoke.script` | Existing script directly under `src/_tests` |
| `smoke.inputs` | Additional file paths/globs, including `src/_tests/_lib.sh` |
| `smoke.policy` | `advisory` reports assertion failures; `required` makes them fatal |

Manifests, Dockerfiles and the declared smoke script automatically participate in impact detection. `inputs` patterns must match existing files. Absolute paths, parent traversal, symlink escapes and directory-wide local COPY instructions are rejected. Local COPY uses one-line shell-form instructions with explicit files; stage/context `COPY --from=` is not a repository input. Keep mirrored Dockerfile defaults synchronized with YAML. Root `README.md` and every image guide need a nonempty `_zh` counterpart; `validate` also checks local guide links.

## Bases and arguments

External base:

```yaml
base:
  image: nvcr.io/nvidia/pytorch:26.06-py3
  digest: null
```

The digest key is required. Use `null` to track an explicit version tag, or `sha256:<64 lowercase hex characters>` to pin its content. `latest`, `master` and untagged external bases are rejected. No upstream digest is invented during migration.

Internal base:

```yaml
base:
  dependency: luciole-cuda-base
```

The named image must exist, its platforms must cover the child's platforms, and its `USERNAME` must match the child. Dependency cycles are rejected. Bake injects `BASE_IMAGE=internal_base` and `contexts.internal_base=target:<dependency>`. `BASE_IMAGE` and compatibility-only `BASE_TAG` are reserved and cannot be set through `build_args`.

The base manifest owns TZ, CMake/library versions, USERNAME, USER_UID, USER_GID and USER_GROUPS (comma-separated existing supplementary groups; empty by default). Final manifests own ROS_DISTRO, ROS_TARGET and USERNAME. Changing an account name requires changing the base and both finals together. Duplicate YAML keys and build arguments not declared by the Dockerfile are rejected. Dev/runtime mirror behavior and SSH behavior remain in the existing scripts; no new mirror or SSH policy interface is introduced.

## Commands and generated formats

Run from the root after `python -m pip install -e '.[dev]'`:

```bash
python -m tools.images validate
python -m tools.images list
python -m tools.images plan --all --output build-plan.json
python -m tools.images plan --image luciole-cuda-dev --output build-plan.json
python -m tools.images plan --base <commit> --head <commit> --output build-plan.json
```

`plan` emits `schema_version`, `changed_files`, topologically ordered `targets` and `build_matrix.include`. Each target has `name`, `platforms`, `publish` and `reason` (`selected` or `dependency`). Consumers validate the plan against current manifests, rejecting a missing ancestor or stale platform list.

`bake --plan <file> --owner <owner> --revision <full-sha> --repository <owner/repository> --platform <platform> --mode load|publish --output <file>` renders a native graph. Owner defaults are not guessed; source repository defaults to `dkuav/images`. Add `--github-cache` only in authenticated Actions execution; local rendering omits remote caches. Load mode never writes caches. Publish mode emits digest-only registry outputs for publish targets and cache-only outputs for ancestors.

`test --plan <file> --owner <owner> --revision <full-sha> --platform <platform>` runs loaded smoke contracts. Tests have no GPU flags and verify container software contracts, not access to GPU hardware. CLI errors return nonzero; advisory suppression applies only to assertions handled by `_lib.sh`.

CI additionally uses `collect --metadata <bake-metadata.json> --output <file>` with plan/owner/revision/platform to collect publishable digests. `merge --digests <directory> --ref <git-ref>` with plan/owner/revision validates artifact completeness before creating manifests. `merge --dry-run` prints Docker command arrays without changing the registry. Digest artifact version 1 records name, platform, digest, owner and full revision.

Generated plans/Bake files are local files or CI artifacts. Main emits the existing seven-character SHA tags, `main` and `latest`; version events add the `v*` tag. These are not new `<family>:<variant>` tags. Retiring a manifest never deletes published registry artifacts.

## Shared component inputs

Initialize the pinned `vendor/image-kit` submodule before validation. List each copied component file explicitly in `inputs`; a missing component input reports `git submodule update --init --recursive`. A change to `.gitmodules` or the component commit pointer rebuilds all images, because Git reports the gitlink path rather than individual changed component files. Shared script files changed directly in a working tree still follow their declared consumers.
