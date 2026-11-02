# Luciole manifest reference

Luciole uses the packaged [v2 schema](../vendor/image-kit/src/image_kit/schemas/image.schema.json)
and shared [field reference](../vendor/image-kit/docs/manifest-reference.md). Run
`uv sync --locked --extra dev`, `images validate` and `python -m tools.check_repository`.
There is one authoritative schema and no consumer-local schema copy.

`name` declares the published package independently of the directory. Each current Luciole
manifest has one explicit variant: `pytorch26.06-py3` for CUDA and the vendor-stack ID for
Ascend. Build arguments and tests live under that variant. Internal bases use
`base.target: luciole-cuda-base/pytorch26.06-py3` and `base.context: internal_base`.
Parent platforms must cover child platforms; USERNAME inheritance is a separate Luciole check.

Luciole smoke tests stay under `src/_tests`, explicitly declare their helper and inputs, use
`entrypoint: image`, and retain advisory base assertions and required final-image assertions.
Account/SSH behavior and CUDA/Ascend installation boundaries remain in existing Dockerfiles and
scripts. COPY inputs and ARG wiring are checked locally; helper paths and graph semantics are
validated by image-kit. READMEs are bilingual; `docs/` is English-only.

Use `images plan --target luciole-cuda-dev/pytorch26.06-py3` or `--all`, then native
`bake --platform linux/amd64 --mode load` and `build-test` with the same identity. See the shared
[CLI and artifact contract](../vendor/image-kit/docs/cli-reference.md) for publication and release.
