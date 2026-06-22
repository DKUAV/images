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

`ucs_config_doc_nop` is a UCX core symbol that lives in `libucs.so`.

## 2. Root cause: HPC-X v2.20 ships mismatched UCX 1.17 / UCC 1.4 on arm64

> ⚠️ **This is an upstream NVIDIA NGC bug**, NOT something wrong with how this
> repo registers ld.so paths. Earlier drafts of this doc (now superseded)
> blamed ld.so.cache staleness or missing ld.so.conf entries; both were
> disproved by the diagnostic dump in `run.log` (kept under the same repo for
> reference). The real story:

### 2.1 The version skew in NVIDIA HPC-X v2.20 (arm64)

`/opt/hpcx/VERSION` on this image reads:

```
HPC-X v2.20
ucc-...  1.4.0
ucx-39c8f9b  1.17.0
```

**UCC 1.4.0 was compiled against symbols present in UCX 1.18+** (notably
`ucs_config_doc_nop`, added in the UCX 1.18 release). But the UCX that ships
**in the same HPC-X bundle is 1.17.0** — one minor version behind. So on
arm64:

- `libucc.so.1` references `ucs_config_doc_nop` (compiled in)
- `libucs.so.0` everywhere on disk (both `/opt/hpcx/ucx/lib/libucs.so.0`
  and `/lib/aarch64-linux-gnu/libucs.so.0`) **does NOT export it**
  (confirmed by `nm -D <libucs> | grep ucs_config_doc_nop` returning 0
  matches across every copy on disk)

There is, in other words, **no libucs on this image that can satisfy
libucc**. This is a packaging bug in NVIDIA NGC pytorch:24.10-py3 (arm64);
amd64 not affected.

### 2.2 Why this surfaces as a torch import error

torch itself does **not** use HPC-X's libucc/libucx. But when torch's `_C`
is `dlopen`'d, the dynamic linker walks the global ld.so search path for any
of torch's dependencies. `LD_DEBUG=libs python3 -c "import torch"` shows
libucc.so.1 is found via `/opt/hpcx/ucc/lib/libucc.so.1`, which NVIDIA
pre-registered in `/etc/ld.so.conf.d/hpcx.conf`. Loading it then fails the
symbol resolution described in 2.1, which propagates up as the torch
ImportError.

Note that ld.so.cache was **already correctly built**: NVIDIA's `hpcx.conf`
exists on both arches, and `ldconfig -p` lists both `libucc.so.1 →
/opt/hpcx/ucc/lib/libucc.so.1` and `libucs.so.0 → /opt/hpcx/ucx/lib/libucs.so.0`.
The cache did "the right thing" — it pointed to the only libucc on disk. The
problem is at the binary level, not the cache level.

### 2.3 Recap of what didn't work

- `RUN ldconfig` at the end of the Dockerfile — fixed the *unrelated*
  amd64-base issue (some libs not in cache) but **not** arm64 base.
- A dynamic-discovery `zz-ngc-extra.conf` re-registering all HPC-X lib paths —
  irrelevant: NVIDIA's own `hpcx.conf` already registered them. The issue
  is the libraries themselves,
  not their registration.

## 3. Why Tier 2 images "worked by accident"

Both Tier 2 Dockerfiles call `ros2.sh`, which does:

```bash
apt-get -y install ros-${ROS_DISTRO_VAL}-${ROS_TARGET_VAL}
apt-get -y install ros-dev-tools
```

ROS 2's transitive apt deps pull in a system-ports version of `libucs`
under `/usr/lib/aarch64-linux-gnu/`. Because the system lib path sorts
earlier in ld.so.conf than NVIDIA's `hpcx.conf`, the dynamic linker prefers
it. That system `libucs` is **old enough to be the dominant match, and on
some ROS 2 releases the system `libucs` had `ucs_config_doc_nop`** while
NVIDIA's HPC-X `libucs` did not — so importing torch on Tier 2 arm64 happened
to succeed. On base, no ROS 2 → no system libucs → no workable fallback →
torch fails.

Don't rely on this. Both Tier 2 arm64 cases were accidental; bumping ROS 2
or removing ROS 2 from the image would re-break them.

## 4. The fix: unregister HPC-X's libucc / libucx paths from ld.so

The cleanest fix is to make torch not see HPC-X's broke libucc/libucx at
all. They are NOT in torch's RPATH; torch only loads them by accident
because `/etc/ld.so.conf.d/hpcx.conf` (NVIDIA-provided)
registered `/opt/hpcx/ucc/lib` and `/opt/hpcx/ucx/lib` in the global search
path.

In `src/luciole-cuda-base/Dockerfile`, the final `RUN` after every
installer script now:

1. **Strips `/opt/hpcx/{ucc,ucx}/lib`** from `hpcx.conf` (sed delete).
2. Writes a NEW `zz-ngc-extra.conf` that registers every *other* vendor
   `.so` tree (CUDA toolkit, TensorRT, hpcx/{hcoll,ompi,sharp,
   nccl_rdma_sharp_plugin}, ROS, `/usr/local/lib`), but explicitly NOT the
   two broken HPC-X comm-lib dirs.
3. Runs `ldconfig`.

```dockerfile
RUN sed -i -E '\@^/opt/hpcx/(ucc|ucx)/lib$@d' \
        /etc/ld.so.conf.d/hpcx.conf 2>/dev/null || true \
    ; find \
        /opt/hpcx/hcoll \
        /opt/hpcx/ompi \
        /opt/hpcx/sharp \
        /opt/hpcx/nccl_rdma_sharp_plugin \
        /opt/tensorrt \
        /opt/nvidia \
        /opt/ros \
        /usr/local/lib \
        -type f -name '*.so*' 2>/dev/null \
        | xargs -r dirname \
        | sort -u > /etc/ld.so.conf.d/zz-ngc-extra.conf \
    ; ldconfig
```

### Why this is correct

- torch no longer resolves `libucc.so.1` from `/opt/hpcx/ucc/lib` →
  nothing in its search chain references the broken symbol chain.
- Other HPC-X users (MPI workers) don't lose anything: they `source
  /opt/hpcx/.../hpcx-init.sh` themselves, which exports `LD_LIBRARY_PATH`
  with the full HPC-X prefix at runtime — independent of ld.so.conf.d.
- amd64 is unaffected (sed is a no-op; the HPC-X libs there are internally
  consistent).
- All other HPC-X libs (hcoll, ompi, sharp, nccl_rdma_sharp_plugin) stay
  registered — only the two broken comm libs are removed.

### Where this runs

- `src/luciole-cuda-base/Dockerfile`: writes `hpcx.conf` patch +
  `zz-ngc-extra.conf` + `ldconfig` as the final step of the base image —
  fixes standalone use of the base image on arm64 (the original failure).
- `src/luciole-cuda-dev/Dockerfile`, `src/luciole-cuda-runtime/Dockerfile`:
  inherit the patched conf from base; they also run `RUN ldconfig` once more
  at their own end so any extra `.so` files introduced by `ros2.sh`,
  `clang.sh`, and `devshell.sh` (only dev) land in the cache. They never
  re-add `hpcx/ucc/lib` or `hpcx/ucx/lib`.

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

- 2026-06-19 — added a final `RUN ldconfig` to all three Dockerfiles. Fixed
  amd64 base torch import. Did **not** fix arm64 base.
- 2026-06-22 (a) — replaced the bare `ldconfig` with a dynamic-discovery
  `zz-ngc-extra.conf` write + `ldconfig` in `luciole-cuda-base/Dockerfile`.
  Did **not** fix arm64 base either.
- 2026-06-22 (b) — ran the `.github/workflows/diag-arm64-torch.yml`
  diagnostic on a native arm64 GH runner against
  `ghcr.io/dkuav/luciole-cuda-base:latest`. The dump revealed the **real**
  root cause: NVIDIA HPC-X v2.20 ships UCX 1.17 with UCC 1.4 — incompatible
  symbol (`ucs_config_doc_nop`) — on arm64. Subsequent fix: strip
  `/opt/hpcx/{ucc,ucx}/lib` from `hpcx.conf` and keep them out of
  `zz-ngc-extra.conf`. Tier 2 images retain their own final `ldconfig` as a
  safety net.
