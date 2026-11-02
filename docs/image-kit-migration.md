# Unified build-engine migration

This migration replaces the earlier dual-format adapter with image-kit 0.2 and one v2 schema,
model, plan and CLI. Both consumers migrate together; the native repository/CLI adapters and
`manifest-format` switch are removed. See [the shared migration guide](../vendor/image-kit/docs/migration-v2.md)
and [current architecture](build-architecture.md).

The YAML name is authoritative and independent of directories. Existing package names remain;
Luciole variants explicitly identify their PyTorch or Ascend stack. All active references move
directly to variant channels. Old aliases and artifacts are retained but no longer updated.
Installation versions/order, SSH policy, account defaults and smoke assertions are unchanged.

Publish the reviewed component first, then update both consumer pins and run their CI. Until
the component is published and pins updated, this worktree depends on the modified submodule.
Existing unrelated consumer changes must be preserved. No automatic commit, push, registry
deletion or image publication is part of local implementation.
