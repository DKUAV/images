# ld.so.cache Notes — CUDA / PyTorch / HPC-X dlopen errors

> Status: **landed in PR #24** · Owner: DKUAV Images
>
> 📌 Records the root cause, the asymmetric behaviour across arches, and the
> generic fix used to keep `import torch` (and any other dlopen-heavy import)
> working on both amd64 and arm64 `luciole-cuda-*` images.
>
> 中文版：[ld-cache-notes_zh.md](./ld-cache-notes_zh.md)

This document captures why `import torch` failed on the arm64
`luciole-cuda-base` image built on top of `nvcr.io/nvidia/pytorch:24.10-py3`,
and why the Tier 2 images (`luciole-cuda-dev`, `luciole-cuda-runtime`) on the
same arch happened to work by accident. It also documents the generic fix
applied to all three Dockerfiles so future NGC packages don't reintroduce the
same class of bug.

## 1. Symptom

CI smoke tests on `luciole-cuda-base` (arm64) failed at:

```
✗ torch importable (exit 1)
       command: python3 -c import torch; print(...)
       output: Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/usr/local/lib/python3.10/dist-packages/torch/__init__.py", line 368, in <module>
    from torch._C import *  # noqa: F403
ImportError: /opt/hpcx/ucc/lib/libucc.so.1: undefined symbol: ucs_config_doc_nop
```

`ucs_config_doc_nop` is a HPC-X symbol defined in `libucs.so` (the UCX core).
`libucc.so.1` expects it but, when torch dlopen()s `_C`, the dynamic linker
loaded a version of `libucc` whose sibling `libucs` doesn't provide the symbol.

## 2. Root cause: ld.so.cache staleness + missing ld.so.conf registration

Two independent conditions have to line up for the failure, both baked into
how Docker layering interacts with `ldconfig`:

### 2.1 ld.so.cache is snapshotted per Docker layer

Each Dockerfile `RUN` produces a layer whose filesystem snapshot includes
`/etc/ld.so.cache` **as it was at the end of that RUN**. Subsequent RUNs that
add `.so` files do so on top of a now-stale cache unless they re-run
`ldconfig` themselves. So if e.g. `opencv.sh` runs `ldconfig` and later
`pip-packages.sh` drops new `.so` files, those new files are **not** in the
cache that the final owning layer sees.

This alone is fixable by appending `RUN ldconfig` everywhere — and that
sufficed for lots of containers. But it was *not* sufficient here, because of
condition #2.

### 2.2 ldconfig only scans paths declared in ld.so.conf

`ldconfig` does **not** walk the whole filesystem. It scans:

- `/usr/lib` and the multiarch triplet (`/usr/lib/x86_64-linux-gnu`,
  `/usr/lib/aarch64-linux-gnu`, …)
- every file `/etc/ld.so.conf` includes, in turn everything under
  `/etc/ld.so.conf.d/*.conf`

So **`RUN ldconfig` is only as good as the conf files let it be.** If a
vendor puts `.so` files under a directory that isn't on any conf line,
`ldconfig` will never register them — no matter how many times you run it.

### 2.3 The asymmetry: NVIDIA pre-registers on amd64 but not on arm64

NVIDIA's NGC `pytorch:24.10-py3` image ships the HPC-X stack
(UCX, UCC, Sharp, …) under `/opt/hpcx/...`:

- On **amd64**, they pre-register every `lib` subdirectory via
  `/etc/ld.so.conf.d/...` files. `ldconfig` therefore picks them up.
- On **aarch64 / Jetson L4T**, the equivalent conf entries are **missing**
  in current NGC releases. `ldconfig` has nothing to scan and the cache
  silently knows nothing about HPC-X.

This is a long-standing complaint about Jetson NGC images and is completely
invisible until a binary (`import torch`) actually dlopen()s into the affected
`.so` chain.

## 3. Why Tier 2 images "worked by accident"

Both Tier 2 Dockerfiles call `ros2.sh`, which does:

```bash
apt-get -y install ros-${ROS_DISTRO_VAL}-${ROS_TARGET_VAL}
apt-get -y install ros-dev-tools
```

Installing ROS 2 pulls in a large closing set of shared-library dpkg
packages. **dpkg, after any package that ships `.so` files, runs `ldconfig`
as a maintainer script trigger.** That implicit trigger ran at the tail of
`apt-get install ros-…`, and:

1. It refreshed the ld.so.cache for that layer.
2. ROS 2's transitive deps also pulled in system-ports versions of
   `libucc` / `libucs` under `/usr/lib/aarch64-linux-gnu` (the default-triplet
   path, which *is* registered by default). Those showed up at a higher
   preload priority than the missing-from-cache `/opt/hpcx/...` ones, so the
   dlopen chain happened to resolve to a self-consistent pair.

On the base image — which doesn't run `ros2.sh` — neither side effect fires.
On amd64 base, NVIDIA's own ld.so.conf entries cover HPC-X, so it still works.
On arm64 base, neither covers anything. Hence the matrix:

| Image          | amd64                                | arm64                                                    |
|----------------|--------------------------------------|----------------------------------------------------------|
| `luciole-cuda-base`     | ✓ — NVIDIA pre-registers HPC-X | ✗ — no ros2 trigger, no NVIDIA registration → torch fails |
| `luciole-cuda-dev`      | ✓ — both effects cover it     | ✓ — ros2.sh's dpkg trigger happened to repair the cache  |
| `luciole-cuda-runtime`  | ✓ — both effects cover it     | ✓ — same as dev                                          |

Both surviving arm64 cases were **accidental**, depending on the specific
ROS 2 dependency graph of `ros-humble-ros-base`. A future ROS 2 release, or
the same image used without ROS 2 sourced, would re-break.

## 4. The generic fix: dynamic ld.so.conf discovery + ldconfig

In `src/luciole-cuda-base/Dockerfile`, the final `RUN` after every installer
script now writes a single file — `/etc/ld.so.conf.d/zz-ngc-extra.conf` —
containing **every directory that actually contains a `.so` file** under the
NVIDIA /opt vendor roots and `/usr/local/lib`, then runs `ldconfig`:

```dockerfile
RUN find \
        /opt/hpcx \
        /opt/tensorrt \
        /opt/nvidia \
        /opt/ros \
        /usr/local/lib \
        -type f -name '*.so*' 2>/dev/null \
        | xargs -r dirname \
        | sort -u > /etc/ld.so.conf.d/zz-ngc-extra.conf \
    ; ldconfig
```

### Why this is robust

- **Dynamic discovery, not a hardcoded list** (`ucx/lib`, `ucc/lib`,
  `sharp/lib`, …). It survives HPC-X internal path renames and future NGC
  packages dropped under `/opt/<newthing>` without anyone having to update
  this Dockerfile.
- `-type f -name '*.so*'` filters to directories that **actually contain a
  shared object**, so empty `lib/` placeholders inside `/opt/nvidia` etc.
  don't pollute the conf.
- `xargs -r dirname | sort -u` emits one absolute path per line with no
  duplicates — exactly the ld.so.conf.d format.
- `zz-` prefix sorts this conf last, so when NVIDIA or Ubuntu add their own
  conf later they take priority over us for same-named libs we don't want to
  shadow.
- `2>/dev/null` makes the command tolerate missing top-level directories
  (e.g., images without `/opt/tensorrt`).
- Architecture-agnostic: the same command produces amd64-only entries on
  amd64 and arm64-only entries on arm64, because `find` only emits paths that
  actually exist in the image being built.

### Where this runs

- `src/luciole-cuda-base/Dockerfile`: writes `zz-ngc-extra.conf` and runs
  `ldconfig` as the final step of the base image — fixes standalone use of
  the base image on arm64 (the original failure).
- `src/luciole-cuda-dev/Dockerfile`, `src/luciole-cuda-runtime/Dockerfile`:
  inherit the conf from base; they also run `RUN ldconfig` once more at their
  own end so any extra `.so` files introduced by `ros2.sh`, `clang.sh`, and
  `devshell.sh` (only dev) land in the cache.

## 5. Verification

After this change, smoke tests across all six cells of the matrix above pass:

- `src/_tests/smoke-base.sh` runs `python3 -c "import torch"` on both arches.
- `src/_tests/smoke-runtime.sh`, `src/_tests/smoke-dev.sh` also test torch
  transitively.

Future regressions are caught because **smoke tests run on the published
:native-arch runner** with no `--privileged` / no `LD_LIBRARY_PATH` overrides,
so any dlopen failure surfaces identically to what an end user pulling the
image would see. (We deliberately did *not* patch `LD_LIBRARY_PATH` — that
would mask the bug for users who don't source the right `profile.d` script.)

## 6. Generalisation: any future "undefined symbol" on CUDA/ML images

The mental model this document records is a checklist the next time torch or
another ML import fails with `undefined symbol: <something>` in a CUDA
container:

1. **Is the symbol's defining `.so` actually registered in ld.so.conf.d?**
   Inspect with `find /opt -name '*.so*' | xargs dirname | sort -u` and
   compare to `ldconfig -p | grep -E '<lib>` `. Discrepancy = path not
   registered → add it.
2. **Did you run `ldconfig` after the installer that dropped the `.so`?**
   Every `RUN` that installs shared libs should end with `ldconfig` (or be
   covered by a final `RUN ldconfig` in the Dockerfile).
3. **Is the same library present in two forms (e.g. system apt vs. NVIDIA
   bundled)?** If `ldconfig -p | grep libucc` shows two entries, the first
   one wins at dlopen time; the fix is usually either to remove the
   duplicate or to make sure the version you want sorts earlier in conf
   order (lower-case prefix < `zz-`).

The Docker base image community calls these "missing ld.so.conf entries from
<a-vendor-image>" bugs; the maintainer's stance is that vendors (NVIDIA
included) should ship their own conf, but in practice every DKUAV-style
shield image ends up doing this discovery pass once.

## 7. Update log

- 2026-06-19 — added `RUN ldconfig` to all three Dockerfiles. Fixed amd64
  (`luciole-cuda-base`) torch import. Did **not** fix arm64 base.
- 2026-06-22 — replaced the bare `ldconfig` with the dynamic-discovery
  `zz-ngc-extra.conf` write + `ldconfig` in `luciole-cuda-base/Dockerfile`.
  Now fixes arm64 base standalone. Tier 2 images were already passing (by
  accident); they keep a redundant final `ldconfig` as a safety net and to
  register their own additions (`/opt/ros/...` from ros2.sh, `.so` from
  clang/devshell).
