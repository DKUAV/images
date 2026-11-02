---
name: add-install-step
description: Add dependencies, installation steps, or build-time assets to container images in this repository. Use when choosing between image-local files, Luciole-shared extensions, and reusable image-kit capabilities, or wiring them into Dockerfiles and manifests.
---

# Add an Image Dependency or Installation Step

Read the root `AGENTS.md` and inspect the affected image's Dockerfile, `image.yml`,
existing inputs, and smoke tests before choosing a location. Preserve existing work.

## Choose Ownership First

Separate the installation mechanism from the packages and configuration an image selects.

| Scope | Location | Contents |
|---|---|---|
| Reusable across repositories | `vendor/image-kit/scripts/<category>/`, `vendor/image-kit/assets/` | Consumer-independent installers and container resources; deliberately shared default toolsets |
| Shared by Luciole images | `src/_scripts/<category>/`, `src/_assets/` | Luciole-specific installation logic and shared dependency lists or configuration |
| Specific to one image | `src/<image>/` | Image requirements, installation scripts, and configuration |

- Keep a single image's Python dependencies in `src/<image>/requirements.txt`.
  If multiple images actually need the same set, consider a descriptive requirements
  file under `src/_assets/` instead. Publicly available software does not automatically
  belong in image-kit's default package set.
- Reuse installation mechanisms independently of dependency lists. For example,
  `ascend-python-packages.sh` belongs to image-kit, while the requirements it installs
  belong to the consumer. The existing `utils/images` Ascend PEFT image follows this
  pattern; inspect the current checkout before copying an example from another repository.
- Promote logic to a shared location only when its consumers need the same semantics.
  Do not introduce a new abstraction for hypothetical reuse or move existing files
  merely to make layouts look alike.
- Use capability names without sequence numbers. Shared script categories are
  `system`, `dev`, `python`, `libraries`, and `integrations`; retain `cuda-` or
  `ascend-` prefixes where installation behavior differs by platform.

## Choose the Smallest Implementation

- For additional Python packages, edit the appropriate requirements file and reuse
  an existing installer. Do not add a wrapper solely to forward the same arguments.
- Keep a short, direct installation command in the Dockerfile when sufficient.
  Use a script for substantial installation logic, conditional behavior, compilation,
  or configuration. Keep that script image-local unless its scope warrants sharing.
- Determine which image layers need the dependency, including inherited packages.
  CUDA dev and runtime share their CUDA base; Ascend has a separate vendor base.
  Do not add business dependencies to a common base just to reach one final image.
- Preserve vendor-specific behavior. Ascend application packages must use the existing
  constrained installer and package check; do not bypass its recorded base constraints.
  CUDA and Ascend may share a dependency list while retaining different installers.
- When a new script is needed, use `#!/bin/bash`, `set -euo pipefail`, and English
  comments describing its role and execution user. Follow existing GNU `getopt`
  conventions for named options, `--help`, and exit status 64 for invalid usage.
  Pass build arguments as command options rather than persisting them as `ENV`
  unless the value is also needed at runtime. Clean apt lists after installation
  and follow the applicable checksum policy for downloaded binaries.

## Wire the Build and Change Detection

Dockerfiles declare installation order; `image.yml` declares build configuration,
dependencies, copied inputs, and test policy. There is no central dependency map.

- Use the repository root as build context. Copy each independently changeable script
  or asset explicitly and list it in manifest `inputs`; do not copy whole directories.
  Include nested requirements or other files read by the installer as well.
- Keep each capability's `COPY + RUN` instructions adjacent. Put prerequisites first
  and frequently changed business dependencies after stable layers where possible,
  before final mirror configuration and cleanup.
- Run system installation as root. Run user tools as the intended image user and
  return to root for finalization; retain the image's existing final user and entrypoint.
- For component changes, read `vendor/image-kit/AGENTS.md`, validate the component and
  affected consumers, and follow the component-first publication and pinning rules
  in the root `AGENTS.md`. A component pin change rebuilds all consumer images.

For any business image, keep its Python requirements in `src/<image>/requirements.txt`
and choose an installation mechanism compatible with its actual base environment.
The business image's name does not determine which installer it needs.

For example, an Ascend-based business image can reuse `ascend-python-packages.sh`
after its base has provided the Python setup, recorded constraints, and
`ascend-pip-check`. CUDA-based or CPU-only business images should use an installer
or direct command appropriate to their own base. Inspect the installer's contract
before reusing it. Explicitly copy the selected requirements and installer, declare
their source paths in `image.yml`, and preserve cleanup of temporary build inputs.

## Verify and Document

- Add a smoke assertion for the capability the image is intended to provide.
  Importing a Python binding alone does not prove its system executable or library
  works; exercise that integration when it is part of the feature.
- Keep Luciole smoke scripts under `src/_tests` and register their scripts, helpers,
  and additional inputs in the manifest. Preserve existing assertions and policy.
- Run manifest validation and repository policy checks. Run relevant shell checks
  for script changes and component/tooling checks when those surfaces change, using
  the commands in `AGENTS.md`. Report static checks, native container smoke tests,
  and hardware-dependent checks separately.
- Update affected `README.md` / `README_zh.md` pairs together; update all affected
  image guides for a shared feature. Documents under `docs/` remain English-only.
  Update `AGENTS.md` and this skill when maintenance conventions change.
