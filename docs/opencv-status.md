# OpenCV Status & Self-Built Version Analysis

> Status: **Plan A landed** · Branch: `xrc/fix_opencv` · Owner: DKUAV Images
>
> 📌 **Architecture note**: This analysis was written when the repository
> still shipped 3 base families (`luciole-base`, `luciole-cuda-base`,
> `luciole-l4t-base`). The current repository only ships
> `luciole-cuda-base` (+ `luciole-cuda-dev` / `luciole-cuda-runtime`, both
> amd64 + arm64). Historical references to `luciole-base` /
> `luciole-l4t-base` / `luciole-humble-cuda-dev:sha-bca2ba9` below are
> retained verbatim because they describe the build under investigation; the
> OpenCV findings (4.7.0 with missing videoio back-ends) remain valid for
> today's `luciole-cuda-base`.
>
> 📌 **Update (synced to the current branch)**: the repository has now
> collapsed to a single base (`luciole-cuda-base`) with a single downstream
> chain. The original Plan A concerns about "calling opencv.sh in three base
> images" and "coordinating with L4T" no longer apply — `opencv.sh` only
> needs to be called from `luciole-cuda-base`. §4 / §5 / §6 below have been
> rewritten accordingly.
>
> 中文版：[opencv-status_zh.md](./opencv-status_zh.md)

This document records the current state of OpenCV installations across the
Luciole image family, with focus on the root cause, impact and candidate
remediation strategies for the self-built OpenCV 4.7.0 (`/usr/local/lib`) that
ships with broken video I/O back-ends. Submitted for team review.

## 1. Background

The `luciole-cuda-base` image is built on `nvcr.io/nvidia/pytorch:24.10-py3`.
(When this document was written, a sibling plain-Ubuntu `luciole-base` existed
beside it; that image family has since been removed and only
`luciole-cuda-base` remains.) Together with the Tier 2 final layers and
onboarding scripts, the resulting container ends up with **multiple parallel
OpenCV installations**. One of them — the self-built 4.7.0 — ships without
usable video I/O back-ends, so it cannot decode videos that require FFMPEG
(e.g. `vtest.avi`).

This document maps the current state, pinpoints the root cause, and feeds the
follow-up fix decision.

## 2. Inventory of OpenCV installations in the container

Running `ghcr.io/dkuav/luciole-humble-cuda-dev:sha-bca2ba9` (after a series of
OpenCV fix attempts), the container shows three distinct OpenCV installations:

| # | Path | Version | Source | FFMPEG | GStreamer | CUDA | cuDNN | Status |
|---|---|---|---|:---:|:---:|:---:|:---:|---|
| 1 | `/usr/lib/x86_64-linux-gnu/libopencv_*.so.4.5.4d` | 4.5.4 | Ubuntu Jammy apt (pulled in transitively by `ros-humble-desktop`) | ✅ 58.134.100 | ✅ 1.19.90 | ❌ | ❌ | ✅ Can decode video |
| 2 | `/usr/local/lib/libopencv_*.so.4.7.0` | 4.7.0 | **Bundled in NVIDIA `pytorch:24.10-py3` base (self-built)** | ❌ | ❌ | ❌ | ❌ | ⚠️ videoio back-ends missing |
| 3 | `/usr/local/lib/python3.10/dist-packages/cv2/cv2.abi3.so` | 4.11.0.86 | pip `opencv-contrib-python` wheel (ships its own static deps) | ✅ (internal libavcodec 59) | ❌ | ❌ | ❌ | ✅ Python usable |

The Python `import cv2` error (`module 'cv2.dnn' has no attribute 'DictValue'`)
is caused by the cv2 module files of installation #3 colliding with stale
dist-info metadata — an independent secondary issue.

## 3. Details of the self-built OpenCV 4.7.0 issue

### 3.1 Source identification

Multiple independent lines of evidence confirm that
`/usr/local/lib/libopencv_*.so.4.7.0` comes from the **NVIDIA NGC
`pytorch:24.10-py3` base image** rather than any script in this repository:

| Evidence | Command | Result |
|---|---|---|
| Build timestamp | `stat /usr/local/lib/libopencv_core.so.4.7.0` | `2024-10-04` — in sync with pytorch:24.10 release |
| Embedded build time | `getBuildInformation()` | `Timestamp: 2024-10-03T20:49:35Z` |
| Build-path fingerprint | `strings libopencv_videoio.so.4.7.0 \| grep opencv-4.7.0` | `/opencv-4.7.0/modules/videoio/src/cap_*.cpp` — source tree removed, only strings remain |
| Package ownership | `dpkg -S /usr/local/lib/libopencv_core.so.4.7.0` | None (not installed via apt) |
| Build identity | `strings libopencv_core.so.4.7.0 \| grep -i nvidia` | `NVIDIA Corporation` — clearly an NGC build |
| Repository script scan | `grep -ri opencv src/_scripts/` | Only `pip install opencv_python`. **No OpenCV compile step anywhere.** |

### 3.2 Missing video I/O back-ends

Key problem: **the self-built 4.7.0 disables every video decoder back-end at
build time.** The Video I/O section of `cv::getBuildInformation()` reads:

```text
  Video I/O:
    FFMPEG:                      NO
      avcodec:                   NO
      avformat:                  NO
      avutil:                    NO
      swscale:                   NO
      avresample:                NO
    GStreamer:                   NO
    v4l/v4l2:                    YES (linux/videodev2.h)
```

Consequence: the 4.7.0 `cv::VideoCapture` only has V4L2 plus the CAP_IMAGES
fallback, unable to decode any container video. The error surfaces as:

```text
[ERROR:0@0.002] global cap.cpp:164 open VIDEOIO(CV_IMAGES): raised OpenCV exception:
OpenCV(4.7.0) /opencv-4.7.0/modules/videoio/src/cap_images.cpp:253: error:
  (-5:Bad argument) CAP_IMAGES: can't find starting number (in the name of file):
  video/vtest.avi in function 'icvExtractPattern'
```

This is an intentional trade-off NVIDIA made when building the image
(typical NGC images drop GUI / multimedia deps to save space), not a Luciole
configuration mistake.

### 3.3 ABI / soname mismatch

C++ projects such as LucioleCore that link via `find_package(OpenCV)` will by
default hit 4.7.0 first (CMake searches `/usr/local/lib/cmake/opencv4/` before
`/usr/lib`), not the system 4.5.4. The observable effects are:

- The project compiles fine, linking 4.7.0
- At runtime `vtest.avi` cannot be opened, `cv::VideoCapture` fails
- Behaviour contradicts the developer's mental model ("the apt-installed system
  OpenCV should be the one used")

### 3.4 Neither version ships CUDA acceleration

> ⚠️ Critical finding that reshapes the remediation plan selection below.

A common assumption is that "the NVIDIA-bundled OpenCV must come with CUDA /
cuDNN enabled while the Ubuntu apt build does not". Empirical verification
shows the opposite of "either is GPU-accelerated":

**Both** `cv::getBuildInformation()` outputs **have no `NVIDIA CUDA` /
`GPU CUDA architecture target` / `cuDNN` section at all**, and `ldd` of the
respective `libopencv_core.so` links to **no** `libcudart` /
`libcudnn` / `libcublas`:

| Build artifact | CUDA section in `getBuildInformation()` | `ldd` references to CUDA libs |
|---|---|---|
| apt 4.5.4 (`/usr/lib/libopencv_core.so.4.5.4d`) | absent | none |
| NVIDIA 4.7.0 (`/usr/local/lib/libopencv_core.so.4.7.0`) | absent (string `cuda` appears 0 times in the whole build info) | none |
| pip 4.11.0.86 wheel | absent | none |

The apt build is unsurprising — Ubuntu does not ship CUDA-enabled OpenCV by
default. The NVIDIA build is more interesting: although the base image **does**
ship `libcudart`, NVIDIA chose to compile OpenCV without `WITH_CUDA=ON`, in
line with their recommendation that CUDA compute should go through PyTorch /
TensorRT, while OpenCV stays on the CPU side of the pipeline.

**Implication**: any Luciole component that needs `cv::cuda::*`,
`cv::dnn` with CUDA backend, or `cudaimgproc` etc. currently has **no
functioning OpenCV build to link against**. Plans A and B below both address
video I/O but neither delivers GPU acceleration; only the new **Plan E**
does.

## 4. Relationship with the current branch fixes

The `xrc/fix_opencv` branch lands three separate fixes that together turn the
OpenCV situation from a latent risk into a properly resolved state:

1. **Drop the transitive ROS 4.5.4**:
   - `src/_scripts/ros2.sh`: default `ROS_TARGET` changed `desktop` → `base`
   - Final-image Dockerfiles: `ARG ROS_TARGET=desktop` → `base`
     (currently the two `luciole-cuda-dev` and `luciole-cuda-runtime` files)

   After this change Tier 2 images only install the `ros-humble-base` meta-
   package; the dependency tree
   (`apt-cache depends --recurse ros-humble-base`) **contains no opencv
   packages at all**.

2. **Replace NVIDIA's bundled 4.7.0 with the apt build (Plan A, landed)**:
   - New `src/_scripts/opencv.sh`, called **only once** from
     `luciole-cuda-base` (the single-topology payoff: the "three base images"
     cost from when this doc was written fully disappears)
   - Owns C++ OpenCV only; does not touch Python cv2. Details in §5 Plan A.

3. **Fix the Python cv2 double-wheel collision (independent of Plan A)**:
   - `src/_scripts/pip-packages.sh` originally installs both `opencv_python`
     and `opencv-contrib-python` — explicitly warned against by PyPI
     (contrib is a superset of the headless wheel; shipping both causes
     Python `import cv2` to load a module with mismatched internal ABI),
     which is the real root cause of the `cv2.dnn.DictValue` error in §2.
   - After the fix only `opencv-contrib-python` (with FFMPEG + GUI) is
     installed, as the single Python cv2.
   - This fix is independent of the two above in implementation and lives at
     the source (`pip-packages.sh`) rather than in `opencv.sh` — it is
     **not a step of Plan A**.

> ⚠️ **Why the C++ and ROS fixes must land together**
>
> Doing only step 1 and keeping NVIDIA 4.7.0 leaves the container with only
> the 4.7.0 (no FFMPEG) + pip 4.11 (no matching soversion) pair, so C++
> video decoding is broken entirely. Step 2 (Plan A) reintroduces a complete,
> apt-maintained OpenCV in the Tier 1 base as the single C++ resolution
> target.
>
> Conversely, doing only step 2 while keeping `ROS_TARGET=desktop` could
> revive apt 4.5.4 transitively through `ros-humble-desktop`, recreating a
> multi-version state. The two fixes are intentionally interlocking.
>
> Fix #3 (pip wheel dedup) must ship in the same release as either of the
> above so the published image has both a working C++ OpenCV and a clean
> Python cv2, but its implementation belongs in `pip-packages.sh`, not in
> `opencv.sh`.

## 5. Candidate remediation plans

> Reviewed by the team to pick one main-track plan. Listed by recommendation
> order.

### Plan A (recommended, landed): install apt 4.5.4 and quarantine NVIDIA's 4.7.0

This is what the current branch ships. Add `src/_scripts/opencv.sh` and invoke
it **only from `luciole-cuda-base`**. The script only handles the **C++**
OpenCV swap; Python cv2 is out of scope (see §4 fix #3). The Python row below
is included for orientation only:

| Use case | Source | Version | Notes |
|---|---|---|---|
| C++ `find_package(OpenCV)` (owned by this script) | apt `libopencv-dev` | 4.5.4 (FFMPEG + GStreamer) | Integrates with the system ffmpeg/gstreamer; apt ships complete `OpenCVConfig.cmake`, headers, `.so` |
| Python `import cv2` (not owned by this script) | pip `opencv-contrib-python` | 4.11.0.86 | Wheel bundles its own static deps (internal `libavcodec 59`); installed by `pip-packages.sh` |

Two steps:

1. **apt install**: only `libopencv-dev` (4.5.4, FFMPEG + GStreamer enabled),
   landing in `/usr/lib`. **Do not install `python3-opencv`**; see the
   **"Why not `python3-opencv`"** callout below.
2. **Quarantine NVIDIA's 4.7.0**:
   - Move `/usr/local/lib/libopencv_*.so*` to
     `/usr/local/lib/nvidia-opencv-4.7.0.disabled/` (**retained for
     reversibility**, never deleted)
   - Drop lookup entry points: `/usr/local/lib/cmake/opencv4`,
     `/usr/local/lib/pkgconfig/opencv4.pc`, `/usr/local/include/opencv4`
   - `ldconfig` to refresh the dynamic-linker cache

   With `/usr/local` gone from the resolver paths, both `find_package(OpenCV)`
   and `ld.so` fall back to the apt build under `/usr/lib`.

   The pip cv2 wheel is fully static and does not depend on the `/usr/local/lib/*.so`
   files, so it is unaffected by this step.

> **Why not `python3-opencv`**
>
> The container's Python cv2 is provided by the pip `opencv-contrib-python` wheel
> (4.11.0.86, bundles its own static ffmpeg, stays on the PyPI upgrade track).
> Installing `python3-opencv` from apt on top of that would place a second cv2
> into `/usr/lib/python3/dist-packages/cv2/` alongside the pip wheel's
> `/usr/local/lib/python3.x/dist-packages/cv2/`. The two share major version 4
> but differ in minor version and have mismatched internal ABI; `import cv2`
> loads one of them depending on Python's search order, producing a corrupted
> state — essentially the same class of problem as the
> `opencv_python` + `opencv-contrib-python` double-wheel collision described
> in §4 fix #3. The script therefore installs only `libopencv-dev` for C++ and
> never `python3-opencv`.
>
> The apt Python cv2 is also unnecessary for “following upstream”: all Luciole
> Python packages consistently use pip (Aliyun PyPI mirror), so `python3-opencv`
> would just be extra weight.

> **Out of scope for this script**: the pip-side `opencv_python` /
> `opencv-contrib-python` double-wheel fix lives at the source in
> `pip-packages.sh` (§4 fix #3) and should not be conflated with the
> responsibilities of this script.

**About `dpkg-divert` / symlinks**: those names appeared in the original
write-up but are not used in the landed implementation. Rationale: 4.7.0 is not
in the dpkg database (`dpkg -S` returns no owner), and apt 4.5.4 vs NVIDIA 4.7.0
live at disjoint paths (`/usr/lib` vs `/usr/local/lib`), so there is nothing
for `dpkg-divert` to guard. A plain rename + `ldconfig` is sufficient, cleaner,
and fully reversible.

**Pros**

- Cooperates perfectly with the `ROS_TARGET=base` fix; C++ projects decode
  video again
- C++ uses apt, Python uses pip — each on its best track, no forced bundling.
  Image-size growth is minimal (only apt's `libopencv-dev`; no
  `python3-opencv`)
- **Single responsibility**: this script only does the C++ apt install + the
  NVIDIA 4.7.0 quarantine. The Python cv2 double-wheel issue is fixed at the
  source in `pip-packages.sh` (§4 fix #3); the script does not redundantly
  uninstall wheels, avoiding cross-script ownership overlap
- Fully reversible: moving the `.so` libraries, CMake configs, `pkg-config` files, and headers back to their original locations and re-running `ldconfig` perfectly restores the upstream C++ layout for both compile-time and run-time. The Python side is not touched by this script, so no parallel rollback is needed. Rollback commands:
  ```bash
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib/libopencv_*.so* /usr/local/lib/
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib/cmake/opencv4 /usr/local/lib/cmake/
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib/pkgconfig/*.pc /usr/local/lib/pkgconfig/
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/include/opencv4 /usr/local/include/
  # Restore Python bindings if they were quarantined
  cp -r /usr/local/lib/nvidia-opencv-4.7.0.disabled/python/cv2 /usr/local/lib/python3.10/dist-packages/ 2>/dev/null || true
  ldconfig
  ```

**Cons**

- **CUDA / cuDNN acceleration is still missing**: both the C++ apt 4.5.4 and
  the Python pip 4.11 wheel are CPU-only builds. Any Luciole component that
  needs `cv::cuda::*`, CUDA-backed `cv::dnn`, or `cudaimgproc` is out of luck.
  This is the only capability gap vs Plan E.
- C++ and Python OpenCV **versions no longer match** (C++ 4.5.4, Python 4.11);
  consult the API docs per-language when needed. This is not a problem in
  itself: `cv::` and `cv2.` do not share a binary ABI; what matters is that
  each side's API satisfies the consumer.
- Edge-case drift: when NVIDIA ships a newer base image the glob
  `/usr/local/lib/libopencv_*.so*` may need to be re-checked.

### Plan B: rebuild 4.7.0 from source with FFMPEG and GStreamer enabled

Add `src/_scripts/opencv-build.sh`:

- Install `libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
  libgstreamer1.0-dev`
- Fetch the `opencv-4.7.0` source → CMake build → `cmake --install
  /usr/local`, overwriting the NVIDIA 4.7.0

**Pros**

- No version downgrade; keeps the newer 4.7.0 API surface
- Fully controllable build parameters

**Cons**

- Materially longer image build time (~15–20 minutes)
- Higher maintenance cost; OpenCV upstream upgrade pressure
- Tricky coordination with L4T images (Jetson ships an NVIDIA-tuned OpenCV)

### Plan C: drop NVIDIA's 4.7.0 and rely solely on pip `opencv_python`

Simply `rm /usr/local/lib/libopencv_*.so.4.7.0` and
`/usr/local/include/opencv4`, hoping C++ projects' `find_package(OpenCV)`
resolves the pip wheel's `OpenCVConfig.cmake`. But pip wheels **do not ship
`OpenCVConfig.cmake`** at all, so this is unworkable.

**Conclusion**: Plan C is infeasible and only listed for contrast.

### Plan D: keep the status quo, document it

No image changes; just document "install libopencv-dev manually if you need
video decoding".

**Pros**

- Zero maintenance cost

**Cons**

- Violates the "batteries-included" principle
- Forces every downstream project (LucioleCore, etc.) to re-configure

### Plan E: rebuild OpenCV from source with FFMPEG + CUDA + cuDNN

> Addresses the missing GPU acceleration surfaced in §3.4.

Variant of Plan B but with the CUDA stack enabled. Add
`src/_scripts/opencv-cuda-build.sh` and invoke it from the CUDA-series base
images only (`luciole-cuda-base`; the plain-Ubuntu `luciole-base` referenced
here has since been removed from the repo):

- Install build deps: `libavcodec-dev libavformat-dev libavutil-dev
  libswscale-dev libgstreamer1.0-dev`
- CUDA / cuDNN: reuse the `libcudart` / `libcudnn` already shipped by
  `nvcr.io/nvidia/pytorch:24.10-py3`; pass the include paths and lib paths
  discovered via `CUDA_HOME` (`/usr/local/cuda`) and the cuDNN headers under
  `/usr/include/x86_64-linux-gnu/`
- Fetch the OpenCV + `opencv_contrib` source at a pinned tag (e.g. `4.10.0`)
- CMake flags:

  ```cmake
  -DWITH_CUDA=ON
  -DWITH_CUDNN=ON
  -DOPENCV_DNN_CUDA=ON
  -DCUDA_ARCH_BIN=8.9,9.0       # Ada / Hopper; expand per fleet
  -DBUILD_opencv_cudaarithm=ON
  -DBUILD_opencv_cudawarping=ON
  -DBUILD_opencv_cudafeatures2d=ON
  -DBUILD_opencv_cudimgproc=ON
  -DBUILD_opencv_cudacodec=ON
  -DWITH_FFMPEG=ON
  -DWITH_GSTREAMER=ON
  -DBUILD_EXAMPLES=OFF
  -DBUILD_TESTS=OFF
  -DCMAKE_INSTALL_PREFIX=/usr/local
  ```

  (also `OPENCV_EXTRA_MODULES_PATH` pointing at the `opencv_contrib/modules`)

- `cmake --build` + `cmake --install` overwrites NVIDIA's 4.7.0 in `/usr/local`

**Pros**

- The **only** plan that delivers a GPU-accelerated OpenCV
- FFMPEG + GStreamer also re-enabled (so video decoding works too)
- Single canonical OpenCV in `/usr/local` (no more dual version drift)

**Cons**

- Image build time grows significantly (~25–40 min, dominated by nvcc JIT of
  CUDA kernels for each SM target). Cache strategies like ccache and pinning
  the build result in a separate `luciole-opencv-cuda` intermediate layer help.
- Build is heavier: `CUDA_ARCH_BIN` must be pinned per target fleet; expanding
  to many SMs balloons the binary
- L4T (Jetson) is already CUDA-enabled by NVIDIA's own OpenCV build, so this
  script must be **gated off** for the `luciole-l4t-base` line
  > 📌 Note: `luciole-l4t-base` has since been removed from the repository;
  > the gating rule is retained here as guidance in case the L4T line is
  > reintroduced later.

## 6. Decision summary

| Dimension | Plan A (landed) | Plan B | Plan D | Plan E |
|---|---|---|---|---|
| Implementation cost | Low (single Dockerfile) | High | None | High |
| Build time delta | ~+1 min | ~+15 min | None | ~+25–40 min |
| Video I/O works | ✅ | ✅ | ❌ | ✅ |
| **CUDA / cuDNN acceleration** | ❌ (no regression vs. current state) | ❌ | ❌ | ✅ |
| Cost to extend to a future L4T line | Low (just add a gate) | ⚠️ | ✅ | ⚠️ (must skip this script on L4T, which already ships a CUDA-enabled OpenCV) |
| Python cv2 works | ✅ | ⚠️ | ✅ | ⚠️ |
| Long-term maintenance | Low | High | None | High |

**Recommendations**

1. **If Luciole has no current dependency on `cv::cuda::*` / CUDA-backed
   `cv::dnn`**: adopt **Plan A** (already on the current branch). It is the
   lowest-cost path that fixes video I/O, cooperates with the
   `ROS_TARGET=base` change, and does **not** make the CUDA story worse than
   today.
2. **If any component needs GPU acceleration through OpenCV** (e.g. inference
   pipeline using `cv::dnn` with CUDA backend, or `cudaimgproc`): switch to
   **Plan E**. Plan A is reversible — move the `.disabled/` libs back and
   replace `opencv.sh` with `opencv-cuda-build.sh`; no Tier 1 re-architecture
   required.
3. Plans B and D are now effectively superseded: B is dominated by E (which
   delivers strictly more capability at similar build-time cost), D still
   preserves the "no fix" baseline if no decision is reached.

> Decision basis: no confirmed use of OpenCV CUDA modules in Luciole today,
> so Plan A is shipped first as a stopgap. If `cv::cuda::*` / CUDA backend
> demand shows up later, switch to Plan E.

## 7. Verification procedure

Once a plan lands, the post-CI checks should pass:

1. C++:

   ```bash
   # LucioleCore examples/cpp/mini_vehicle/test_opencv_video.cc
   # (find_package(OpenCV) must resolve to the version the chosen plan picks)
   ./test_opencv_video video/vtest.avi
   # Expected: "Decoded frames : 5 / 5"
   ```

2. Python (pip cv2 wheel):

   ```bash
   python3 -c "import cv2; print(cv2.__version__, cv2.__file__)"
   # Expected: no ImportError, cv2.__version__ == 4.11.0.86,
   #           cv2.__file__ under /usr/local/lib/python3.x/dist-packages/cv2/...
   pip list 2>/dev/null | grep -i opencv
   # Expected: only opencv-contrib-python (opencv-python is uninstalled)
   # getBuildInformation() should report FFMPEG: YES (wheel ships a static ffmpeg)
   ```

3. Package ownership:

   ```bash
   ls /usr/local/lib/libopencv_*.so.*       # Should be empty
   ls /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib | head   # NVIDIA libs land here
   dpkg -l | grep opencv                    # Should list only apt libopencv-*
   ```

   `opencv.sh` prints the same checks at the end of its run, doubling as a
   build-time smoke test.

## 8. Related references

- Fix branch: `xrc/fix_opencv` (the `ROS_TARGET` change)
- NVIDIA NGC PyTorch image: https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch
- OpenCV Video I/O back-end docs:
  https://docs.opencv.org/4.x/d0/da7/videoio_overview.html
- LucioleCore test program:
  `examples/cpp/mini_vehicle/test_opencv_video.cc`
