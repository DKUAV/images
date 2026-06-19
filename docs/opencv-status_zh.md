# OpenCV 现状与自编译版本问题分析

> Status: **方案 A 已落地** · Branch: `xrc/fix_opencv` · Owner: DKUAV Images
>
> 📌 **架构说明**：本文写作时仓库还同时发布 3 个 base 家族
> （`luciole-base`、`luciole-cuda-base`、`luciole-l4t-base`）。当前仓库仅
> 发布 `luciole-cuda-base`（以及 `luciole-cuda-dev` / `luciole-cuda-runtime`，
> 均为 amd64 + arm64）。下文中对 `luciole-base` / `luciole-l4t-base` /
> `luciole-humble-cuda-dev:sha-bca2ba9` 的引用按原文保留，因为它们描述的是
> 当时被调查的那份构建；关于 OpenCV 4.7.0 videoio 后端缺失的结论对今天的
> `luciole-cuda-base` 仍然成立。
>
> 📌 **更新（与当前分支同步）**：仓库现已收敛到单 base（`luciole-cuda-base`）
> 单链路。原方案 A 中“需要在三个 base image 都调用 opencv.sh” / “与 L4T 协调”
> 等成本已不再适用——`opencv.sh` 仅需在 `luciole-cuda-base` 一处调用即可。
> 本文 §4 / §5 / §6 已据此重写。
>
> English version: [opencv-status.md](./opencv-status.md)

本文档记录 Luciole 系列镜像中 OpenCV 的安装现状，重点描述自编译
OpenCV 4.7.0（`/usr/local/lib`）出现的 videoio 后端缺失与版本冲突问题的根因、
影响范围与候选修复方案。供团队评审决策。

## 1. 背景

Luciole `luciole-cuda-base` 镜像基于 `nvcr.io/nvidia/pytorch:24.10-py3`。
（本文写作时还存在一个同级、基于纯 Ubuntu 的 `luciole-base`；该镜像家族现已
 全部移除，本仓库仅保留 `luciole-cuda-base`。）该 base 链路与上层 Tier 2 /
 入库脚本叠加后，容器里出现了**多个 OpenCV 安装**并存的情况，
其中自编译的 4.7.0 因 videoio 后端缺失，无法解码 `vtest.avi` 这类需要 FFMPEG 的视频。

本文档梳理现状并定位根因，为后续修复方案提供依据。

## 2. 容器内 OpenCV 安装现状

运行 `ghcr.io/dkuav/luciole-humble-cuda-dev:sha-bca2ba9`（含一系列 OpenCV 修复尝试）后，
容器内存在 3 个独立的 OpenCV 安装：

| # | 安装路径 | 版本 | 来源 | FFMPEG | GStreamer | CUDA | cuDNN | 状态 |
|---|---|---|---|:---:|:---:|:---:|:---:|---|
| 1 | `/usr/lib/x86_64-linux-gnu/libopencv_*.so.4.5.4d` | 4.5.4 | Ubuntu Jammy apt（`ros-humble-desktop` 间接拉入） | ✅ 58.134.100 | ✅ 1.19.90 | ❌ | ❌ | ✅ 可解码视频 |
| 2 | `/usr/local/lib/libopencv_*.so.4.7.0` | 4.7.0 | **NVIDIA `pytorch:24.10-py3` 基础镜像自带（自编译）** | ❌ | ❌ | ❌ | ❌ | ⚠️ videoio 缺后端 |
| 3 | `/usr/local/lib/python3.10/dist-packages/cv2/cv2.abi3.so` | 4.11.0.86 | pip `opencv-contrib-python` wheel（自带全套静态依赖） | ✅ (内部 libavcodec 59) | ❌ | ❌ | ❌ | ✅ Python 可用 |

Python `import cv2` 报错（`module 'cv2.dnn' has no attribute 'DictValue'`）则由
**安装 #3 的 cv2 module 文件** 与 **遗留的 dist-info 元数据冲突**导致，
是另一个独立的次要问题。

## 3. 自编译 OpenCV 4.7.0 的问题详情

### 3.1 来源确认

通过多种证据交叉验证，`/usr/local/lib/libopencv_*.so.4.7.0` 来自
**NVIDIA NGC `pytorch:24.10-py3` 基础镜像**，而非我们仓库内任何脚本所装：

| 证据 | 命令 | 结果 |
|---|---|---|
| 构建时间戳 | `stat /usr/local/lib/libopencv_core.so.4.7.0` | `2024-10-04` — 与 pytorch:24.10 发布同步 |
| 内嵌构建时间 | `getBuildInformation()` | `Timestamp: 2024-10-03T20:49:35Z` |
| 构建路径指纹 | `strings libopencv_videoio.so.4.7.0 \| grep opencv-4.7.0` | `/opencv-4.7.0/modules/videoio/src/cap_*.cpp` — 源码树已删，仅留字符串 |
| 包归属 | `dpkg -S /usr/local/lib/libopencv_core.so.4.7.0` | 无（非 apt 安装） |
| 构建身份 | `strings libopencv_core.so.4.7.0 \| grep -i nvidia` | `NVIDIA Corporation` — 显然来自 NGC 构建 |
| 仓库脚本扫描 | `grep -ri opencv src/_scripts/` | 仅有 `pip install opencv_python`，**没有任何编译 OpenCV 的步骤** |

### 3.2 videoio 后端缺失

关键问题：**自编译的 4.7.0 在构建时禁用了所有视频解码后端**。
`cv::getBuildInformation()` 的 Video I/O 段：

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

后果：4.7.0 的 `cv::VideoCapture` 只剩 V4L2 与 fallback 的 CAP_IMAGES 模式，
无法解码任何容器格式视频。错误现象：

```text
[ERROR:0@0.002] global cap.cpp:164 open VIDEOIO(CV_IMAGES): raised OpenCV exception:
OpenCV(4.7.0) /opencv-4.7.0/modules/videoio/src/cap_images.cpp:253: error:
  (-5:Bad argument) CAP_IMAGES: can't find starting number (in the name of file):
  video/vtest.avi in function 'icvExtractPattern'
```

这是 NVIDIA 镜像构建时的有意取舍（典型 NGC 镜像为压缩体积而禁用 GUI 与多媒体后端），
并非 Luciole 配置错误。

### 3.3 ABI / 主版本错位

LucioleCore 等 C++ 项目若通过 `find_package(OpenCV)` 链接，
CMake 默认会优先在 `/usr/local/lib/cmake/opencv4/` 找到 4.7.0（路径优先级高于 `/usr/lib`），
而非系统提供的 4.5.4。这会导致：

- 项目编译成功，链接到 4.7.0
- 运行期却出现 `vtest.avi` 解不开、`cv::VideoCapture` 失败
- 行为与开发者直觉（"系统 apt 装的 OpenCV 应该被使用"）相反

### 3.4 两个版本都未启用 CUDA 加速

> ⚠️ 关键发现，会重塑下方方案选择。

常见假设是"NVIDIA 自带的 OpenCV 一定启用了 CUDA/cuDNN，而 apt 版没有"。实测给出
反直觉的结果——两边**都没有** GPU 加速：

`cv::getBuildInformation()` 输出中**完全没有** `NVIDIA CUDA` / `GPU CUDA architecture
target` / `cuDNN` 段，对应 `libopencv_core.so` 的 `ldd` 也不引用任何
`libcudart` / `libcudnn` / `libcublas`：

| 构建产物 | `getBuildInformation()` 中的 CUDA 段 | `ldd` 中对 CUDA 库的引用 |
|---|---|---|
| apt 4.5.4（`/usr/lib/libopencv_core.so.4.5.4d`） | 无 | 无 |
| NVIDIA 4.7.0（`/usr/local/lib/libopencv_core.so.4.7.0`） | 无（整段 build info 中字符串 `cuda` 出现 0 次） | 无 |
| pip 4.11.0.86 wheel | 无 | 无 |

apt 版不出意外——Ubuntu 默认不打包 CUDA 启用版的 OpenCV。NVIDIA 版更有意思：
虽然 base image **自带** `libcudart`，但 NVIDIA 在编译 OpenCV 时**没有开**
`WITH_CUDA=ON`，与其推荐做法一致：CUDA 计算走 PyTorch / TensorRT，
OpenCV 仅承担 CPU 侧的图像处理。

**含义**：任何 Luciole 组件若需要 `cv::cuda::*`、CUDA backend 的 `cv::dnn`、
`cudaimgproc` 等模块，**目前没有任何一个可用的 OpenCV 构建可以链接**。
下方方案 A、B 只解决 video I/O，**都交付不了 GPU 加速**；只有新方案 E 才行。

## 4. 与当前分支修复的关系

仓库 `xrc/fix_opencv` 分支处理三个独立问题，但它们正好合在一起把“OpenCV
在迷跡的处理”从潜在风险变为正式修复：

1. **移除 ROS 间接引入的 4.5.4**：
   - `src/_scripts/ros2.sh`：脚本默认 `ROS_TARGET` 从 `desktop` 改为 `base`
   - 最终镜像的 Dockerfile：`ARG ROS_TARGET=desktop` → `base`
     （当前仅 `luciole-cuda-dev` 与 `luciole-cuda-runtime` 两处）

   修复后 Tier 2 镜像只安装 `ros-humble-base` 元包，依赖树
   `apt-cache depends --recurse ros-humble-base` 中**完全不含 opencv**。

2. **以 apt 版替换 NVIDIA 自带 4.7.0（方案 A，已落地）**：
   - 新增 `src/_scripts/opencv.sh`，**仅由 `luciole-cuda-base` 一处**调用
     （单 base 拓扑的红利：相对写作时"三个 base image"的成本完全消失）
   - 只负责 C++ OpenCV；Python cv2 不动。详见 §5 方案 A。

3. **修正 Python cv2 的双 wheel 冲突（与方案 A 互独立）**：
   - `src/_scripts/pip-packages.sh` 原本同时安装 `opencv_python` 和
     `opencv-contrib-python`，违反 PyPI 官方建议（contrib 是 headless 的超集，
     两者并存会让 Python `import cv2` 加载到内部 ABI 不一致的模块）。
     这是本文件 §2 末尾 `cv2.dnn.DictValue` 报错的真实根因。
   - 修复后只装 `opencv-contrib-python`（含 FFMPEG 与 GUI），作为 Python 单一 cv2。
   - 该修复发生与上面两项互不依赖，也只是 Python 侧的问题，不能与 C++
     OpenCV 替换混为一谈，故**不作为方案 A 的一步**。

> ⚠️ **为什么 C++ 与 ROS 两项需同时做**
>
> 仅做第 1 步、保留 NVIDIA 4.7.0，会让容器只剩 4.7.0（缺 FFMPEG）
> + pip 4.11（无主版本匹配）这对组合，C++ 视频解码彻底罢工。
> 第 2 步（方案 A）就是在 Tier 1 base 里重新引入一份完整的、
> apt 维护的 OpenCV，作为 C++ 的唯一解析目标。
>
> 反过来，仅做第 2 步、把 ROS_TARGET 维持在 `desktop` 会让 apt 4.5.4 也
> 可能复活形成再次的多版本。两项修复正好互锁。
>
> 第 3 项（Python wheel 去重）只需与上述任一项同期 ship，才能让出厂镜像
> 同时拿到可用的 C++ OpenCV 与干净的 Python cv2；但它在实现上不在
> `opencv.sh` 中，而是在 `pip-packages.sh` 源头。

## 5. 候选修复方案

> 待团队评审选择一条主线方案；以下按推荐度排序。

### 方案 A（推荐，已落地）：装 apt 4.5.4 并隔离 NVIDIA 自带 4.7.0

仓库当前已采用此方案。在 `src/_scripts/` 新增 `opencv.sh`，**仅由
`luciole-cuda-base` 一处**调用。脚本只负责**C++ OpenCV**的替换；Python cv2
不在本脚本范围内（详见 §4 fix #3）。表内“Python”一行仅供参考：

| 用途 | 源 | 版本 | 说明 |
|---|---|---|---|
| C++ `find_package(OpenCV)`（本脚本负责）| apt `libopencv-dev` | 4.5.4（FFMPEG + GStreamer）| 与系统 ffmpeg/gstreamer 联动；apt 提供完整的 `OpenCVConfig.cmake`、头文件、`.so` |
| Python `import cv2`（不在本脚本范围）| pip `opencv-contrib-python` | 4.11.0.86 | wheel 自带全套静态依赖（内部 `libavcodec 59`），能解码视频；在 `pip-packages.sh` 中安装 |

具体两步：

1. **apt 安装**：仅装 `libopencv-dev`（4.5.4，FFMPEG + GStreamer 均启用），
   落到 `/usr/lib`。**不装 `python3-opencv`**，理由见下面 **“为什么不装 python3-opencv”** 说明。
2. **隔离 NVIDIA 自带 4.7.0**：
   - 把 `/usr/local/lib/libopencv_*.so*` 移到
     `/usr/local/lib/nvidia-opencv-4.7.0.disabled/`（**保留可逆**，不再删）
   - 删除查找入口：`/usr/local/lib/cmake/opencv4`、
     `/usr/local/lib/pkgconfig/opencv4.pc`、`/usr/local/include/opencv4`
   - `ldconfig` 刷新动态链接器缓存

   `find_package(OpenCV)` 和 `ld.so` 都因 `/usr/local` 入口缺失而回退到
   `/usr/lib` 的 apt 版。

   pip cv2 wheel 是全静态的，不依赖 `/usr/local/lib/*.so`，因此不受这步影响。

> **为什么不装 `python3-opencv`**
>
> 容器里 Python cv2 由 pip 的 `opencv-contrib-python` wheel 提供（4.11.0.86，
> 自带静态 ffmpeg、跟 PyPI 升级链对齐）。如果额外 `apt install python3-opencv`，
> 它会安装另一份 cv2 到 `/usr/lib/python3/dist-packages/cv2/`，与 pip wheel 所在的
> `/usr/local/lib/python3.x/dist-packages/cv2/` **并存**。两者主版本号都是 4 但小版本
> 不同、内部 ABI 不一致，`import cv2` 会因 Python 搜索顺序加载到其中之一而获得混乱
> 状态——本质上与§4 fix #3 所述的 `opencv_python + opencv-contrib-python` 双 wheel
> 冲突是同一类问题。所以脚本只装 C++ 用的 `libopencv-dev`，从不装 `python3-opencv`。
>
> apt 版 Python cv2 也不需为“跟随上游”而装：Luciole 的 Python 包恒走 pip（阿里
> 云 PyPI 镜像），`python3-opencv` 在镜像中属于多此一举。

> **不在本脚本范围内**：pip 侧 `opencv_python` 与 `opencv-contrib-python`
> 的双 wheel 冲突修复发生在 `pip-packages.sh` 源头（§4 fix #3），不应与
> 本脚本的职责混为一谈。

**关于 `dpkg-divert` / symlinks**：写作时原文列了这两个名字，实际落地并没
用到。原因：4.7.0 不在 dpkg 数据库里（`dpkg -S` 显示无归属），apt 4.5.4
与 NVIDIA 4.7.0 路径不重叠（一个 `/usr/lib` 一个 `/usr/local/lib`），
`dpkg-divert` 既无法操作 4.7.0 自身、也没有要保护的 apt 文件冲突场景。
纯 rename + ldconfig 就够，反而更干净、完全可逆。

**优点**

- 与 `ROS_TARGET=base` 修复完美配合；C++ 项目即可正常解码视频
- C++ apt 版 + Python pip 版各走各自最佳路径，不强行搭车；体积增加可控
  （只装 apt 的 `libopencv-dev`，不装 `python3-opencv`）
- **职责单一**：本脚本只走 C++ apt 受控安装 + NVIDIA 4.7.0 隔离；Python cv2
  的双重 wheel 问题由 `pip-packages.sh` 源头修复（§4 fix #3），不在本脚本内
  重复卸轮子，避免跨脚本职责重叠
- 完全可逆：把 `.disabled/` 里的 `.so` 库、CMake 配置、`pkg-config` 及头文件全部移回，再执行 `ldconfig` 即可在**编译期**和**运行期**完美恢复上游布局。回滚指令：
  ```bash
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib/libopencv_*.so* /usr/local/lib/
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib/cmake/opencv4 /usr/local/lib/cmake/
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib/pkgconfig/*.pc /usr/local/lib/pkgconfig/
  mv /usr/local/lib/nvidia-opencv-4.7.0.disabled/include/opencv4 /usr/local/include/
  # Restore Python bindings if they were quarantined
  cp -r /usr/local/lib/nvidia-opencv-4.7.0.disabled/python/cv2 /usr/local/lib/python3.10/dist-packages/ 2>/dev/null || true
  ldconfig
  ```
  布局；Python 侧不走本脚本，无需同步回滚

**缺点**

- **CUDA / cuDNN 加速依旧缺失**：C++ apt 4.5.4 与 Python pip 4.11 wheel 都
  不是 CUDA-enabled 构建。任何需要 `cv::cuda::*` / CUDA backend 的
  `cv::dnn` / `cudaimgproc` 的组件都拿不到。这是方案 A 与方案 E 的唯一
  能力差异。
- C++ 与 Python OpenCV 的**版本不再一致**（C++ 4.5.4，Python 4.11），需要
  查阅 API 时分别确认。这本身不是问题：`cv::` 和 `cv2.` 不共享二进制 ABI，
  只要 C++/Python 各自的 API 语义满足业务即可。
- 非主流场景的回退：未来 NVIDIA 基础镜像换版本时需要重新评估
  `/usr/local/lib/libopencv_*.so*` 的命名屏蔽范围。

### 方案 B：从源码重新编译 4.7.0，启用 FFMPEG 与 GStreamer

在 `src/_scripts/` 新增 `opencv-build.sh`：

- 安装 `libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libgstreamer1.0-dev`
- 拉取 `opencv-4.7.0` 源码 → CMake 编译 → `cmake --install /usr/local`
  覆盖 NVIDIA 自带的 4.7.0

**优点**

- 不降级，仍保留 4.7.0 的新 API
- 完全可控的构建参数

**缺点**

- 镜像构建时间显著增加（~15–20 分钟）
- 维护成本高，未来跟随 OpenCV 上游升级压力大
- 与 L4T 镜像（Jetson 已自带 NVIDIA 优化版 OpenCV）的协调复杂

### 方案 C：移除 NVIDIA 自带 4.7.0，纯依赖 pip `opencv_python`

直接 `rm /usr/local/lib/libopencv_*.so.4.7.0` + `/usr/local/include/opencv4`，
让 C++ 项目通过 `find_package(OpenCV)` 找 pip wheel 提供的 OpenCVConfig。
但 pip wheel 通常**不发布 `OpenCVConfig.cmake`**，不可行。

**结论**：方案 C 不可行，仅作为反例列出。

### 方案 D：维持现状，告知用户

不修改镜像，仅在文档中说明"如需视频解码请单独 `apt install libopencv-dev`"。

**优点**

- 零维护成本

**缺点**

- 违反"开箱即用"原则
- 后续 LucioleCore 等项目每次都需要二次配置

### 方案 E：源码重新编译 OpenCV，同时启用 FFMPEG + CUDA + cuDNN

> 直面 §3.4 暴露的 GPU 加速缺失问题。

方案 B 的变体，但额外启用 CUDA 栈。新增 `src/_scripts/opencv-cuda-build.sh`，
**仅**由 CUDA 系列 base image 调用（`luciole-cuda-base`；此处提到的纯 Ubuntu
 `luciole-base` 现已从仓库移除）：

- 安装构建依赖：`libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
  libgstreamer1.0-dev`
- CUDA / cuDNN：直接复用 `nvcr.io/nvidia/pytorch:24.10-py3` 自带的
  `libcudart` / `libcudnn`；通过 `CUDA_HOME`（`/usr/local/cuda`）以及
  `/usr/include/x86_64-linux-gnu/` 下的 cuDNN 头文件传入
- 拉取固定 tag 的 OpenCV + `opencv_contrib` 源码（例如 `4.10.0`）
- CMake 参数：

  ```cmake
  -DWITH_CUDA=ON
  -DWITH_CUDNN=ON
  -DOPENCV_DNN_CUDA=ON
  -DCUDA_ARCH_BIN=8.9,9.0       # Ada / Hopper，按机型扩展
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

  （同时 `OPENCV_EXTRA_MODULES_PATH` 指向 `opencv_contrib/modules`）

- `cmake --build` + `cmake --install` 覆盖 NVIDIA 4.7.0 到 `/usr/local`

**优点**

- **唯一**能交付 GPU 加速 OpenCV 的方案
- 同时重新启用 FFMPEG + GStreamer（视频解码一并可用）
- `/usr/local` 单 OpenCV，消除多版本漂移

**缺点**

- 镜像构建时间显著拉长（~25–40 分钟，主要消耗在 nvcc 对每个 SM target 的
  kernel JIT）。可以考虑 ccache、或把结果作为 `luciole-opencv-cuda` 中间层镜像缓存
- 构建参数更重：`CUDA_ARCH_BIN` 必须按 fleet 钉死；扩展到多 SM 会让二进制
  体积膨胀
- L4T（Jetson）已用 NVIDIA 自己编译的 CUDA-enabled OpenCV，所以该脚本必须
  **被门控跳过**，不能用到 `luciole-l4t-base` 这条链路
  > 📌 说明：`luciole-l4t-base` 现已从仓库移除；这里保留该门控说明
  > 作为未来若重建 L4T 线路时的参考。

## 6. 决策建议

| 维度 | 方案 A（已落地）| 方案 B | 方案 D | 方案 E |
|---|---|---|---|---|
| 实现成本 | 低（单 Dockerfile）| 高 | 无 | 高 |
| 构建耗时 | ~+1 min | ~+15 min | 无 | ~+25–40 min |
| 视频 I/O 可用 | ✅ | ✅ | ❌ | ✅ |
| **CUDA / cuDNN 加速** | ❌（相对现状不退化）| ❌ | ❌ | ✅ |
| 未来若重建 L4T 的改造代价 | 低（重建时再加门控即可）| ⚠️ | ✅ | ⚠️（需要为 L4T 跳过本脚本，L4T 已自带 CUDA-enabled OpenCV）|
| Python cv2 可用 | ✅ | ⚠️ | ✅ | ⚠️ |
| 长期维护 | 低 | 高 | 无 | 高 |

**建议**

1. **若 Luciole 当前不依赖 `cv::cuda::*` / CUDA backend 的 `cv::dnn`**：
   采用 **方案 A**（当前分支已落地）。这是修复 video I/O 的最低成本路径，
   与 `ROS_TARGET=base` 修复协同，且在 CUDA 这件事上**不比今天更糟**。
2. **若任何组件确实需要 GPU 加速的 OpenCV**（例如推理走
   `cv::dnn` CUDA backend，或使用 `cudaimgproc`）：切到 **方案 E**。
   方案 A 的实现可逆——把 `.disabled/` 里的 .so 移回、再把 `opencv.sh`
   替换成 `opencv-cuda-build.sh` 即可，不需要重新规划 Tier 1 布局。
3. 方案 B 和 D 现在已被取代：B 被 E 全面支配（同样的构建时间，E 能力更强），
   D 仅作为"暂不做决定"的兜底。

> 决策依据：当前 Luciole 未确认有用到 OpenCV CUDA 模块的真实场景，
> 故先落地方案 A 止血；未来出现 cv::cuda::* / CUDA backend 需求时切方案 E。

## 7. 验证手段

任何方案落地后，应在镜像 CI 后通过以下检查：

1. C++：

   ```bash
   # LucioleCore examples/cpp/mini_vehicle/test_opencv_video.cc
   # （编译时 find_package(OpenCV) 解析到的版本应等于方案所采用版本）
   ./test_opencv_video video/vtest.avi
   # 期望: "Decoded frames : 5 / 5"
   ```

2. Python（pip cv2 wheel）：

   ```bash
   python3 -c "import cv2; print(cv2.__version__, cv2.__file__)"
   # 期望: 无 ImportError，cv2.__version__ == 4.11.0.86，
   #       cv2.__file__ 指向 /usr/local/lib/python3.x/dist-packages/cv2/...
   pip list 2>/dev/null | grep -i opencv
   # 期望: 仅 opencv-contrib-python（opencv-python 已 uninstall）
   # getBuildInformation() 中 FFMPEG 应为 YES（wheel 自带静态 ffmpeg）
   ```

3. 包归属：

   ```bash
   ls /usr/local/lib/libopencv_*.so.*       # 应为空
   ls /usr/local/lib/nvidia-opencv-4.7.0.disabled/lib | head   # NVIDIA 库应在此
   dpkg -l | grep opencv                    # 应仅列出 apt 的 libopencv-*
   ```

   `opencv.sh` 末尾会自动跑一遍上述检查并打印结果，可作为构建时的 smoke test。

## 8. 相关引用

- 修复分支：`xrc/fix_opencv`（`ROS_TARGET` 修复）
- NVIDIA NGC PyTorch 镜像：https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch
- OpenCV Video I/O backend 文档：
  https://docs.opencv.org/4.x/d0/da7/videoio_overview.html
- LucioleCore 测试代码：
  `examples/cpp/mini_vehicle/test_opencv_video.cc`
