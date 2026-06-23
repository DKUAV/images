# ld.so.cache 备忘录 — CUDA / PyTorch / HPC-X 的 dlopen 报错

> 状态：**已在 PR #24 落地** · 所有者：DKUAV Images
>
> 📌 记录根因、跨架构的不对称表现，以及在 amd64 与 arm64 下让 `import torch`
> （以及任何重度依赖 dlopen 的 import）都能正常工作的通用修复方案。
>
> English version: [ld-cache-notes.md](./ld-cache-notes.md)

本文记录：为什么基于 `nvcr.io/nvidia/pytorch:24.10-py3` 构建的 arm64
`luciole-cuda-base` 镜像上 `import torch` 会失败；同一架构下的 Tier 2 镜像
（`luciole-cuda-dev`、`luciole-cuda-runtime`）为什么"恰好"又是好的；并归档所有
三个镜像采用的通用修复，使未来的 NGC 包不会再引发同类 bug。

## 1. 现象

`luciole-cuda-base`（arm64）在 CI smoke 测试中出现：

```
✗ torch importable (exit 1)
       command: python3 -c import torch; print(...)
       output: Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/usr/local/lib/python3.10/dist-packages/torch/__init__.py", line 368, in <module>
    from torch._C import *  # noqa: F403
ImportError: /opt/hpcx/ucc/lib/libucc.so.1: undefined symbol: ucs_config_doc_nop
```

`ucs_config_doc_nop` 是 HPC-X 里 `libucs.so`（UCX 核心）提供的符号。
`libucc.so.1` 期望它，但在 torch 经 dlopen() 加载 `_C` 时，动态链接器加载的
`libucc` 对应的同源 `libucs` 里却没有这个符号（版本/路径不匹配）。

## 2. 根因：HPC-X v2.20 arm64 版本里 UCX 1.17 与 UCC 1.4 版本不匹配

> ⚠️ **这是上游 NVIDIA NGC 镜像的打包 bug**，不是本仓库配置 ld.so 路径出错。
> 本文档的早期版本（现已作废）曾把锅扣到 "ld.so.cache 过期" 或 "ld.so.conf 未注册" 上，
> 两者都被 `run.log`（保留在同仓库作为参考）里的诊断 dump 否定了。真实情况：

### 2.1 NVIDIA HPC-X v2.20 arm64 的版本错配

镜像里 `/opt/hpcx/VERSION` 内容为：

```
HPC-X v2.20
ucc-...  1.4.0
ucx-39c8f9b  1.17.0
```

**UCC 1.4.0 编译时使用的是 UCX 1.18+ 才有的符号**（特别地 `ucs_config_doc_nop`
是在 UCX 1.18 引入的）。但同一个 HPC-X bundle 里**同时附带的 UCX 却是 1.17.0**
——落后一个小版本。所以在 arm64 上：

- `libucc.so.1` 引用了 `ucs_config_doc_nop`（编译时被装入）
- 镜像上所有 `libucs.so.0`（无论 `/opt/hpcx/ucx/lib/libucs.so.0` 还是
  `/lib/aarch64-linux-gnu/libucs.so.0`）**都不提供该符号**
  （已由 `nm -D <libucs> | grep ucs_config_doc_nop` 在镜像上所有副本上返 0 证实）

也就是说，**镜像上没有任何一份 libucs 能满足 libucc**。这是 NVIDIA NGC
pytorch:24.10-py3（arm64）的打包 bug；amd64 不受影响。

### 2.2 为什么会报成 torch import 错误

torch 本身**不使用** HPC-X 的 libucc/libucx。但 torch `_C` 被 `dlopen` 时，
动态链接器会沿全局 ld.so 搜索路径查找 torch 的依赖。`LD_DEBUG=libs python3 -c
'import torch'` 显示 libucc.so.1 是从 `/opt/hpcx/ucc/lib/libucc.so.1` 被找到的
——因为 NVIDIA 把 `/opt/hpcx/ucc/lib` 预注册到了 `/etc/ld.so.conf.d/hpcx.conf`。
加载它之后 §2.1 所述的符号未解析错误就出现了，最后以 torch ImportError 的形式
浮上来。

注意：**ld.so.cache 本身已经构造正确**。NVIDIA 的 `hpcx.conf` 在两个架构上都存在，
`ldconfig -p` 同时列了 `libucc.so.1 → /opt/hpcx/ucc/lib/libucc.so.1` 和
`libucs.so.0 → /opt/hpcx/ucx/lib/libucs.so.0`。cache 干了"正确的事"——指向
镜像上唯一的副本。问题在二进制本身，不在缓存。

### 2.3 哪些尝试不凑效

- 在 Dockerfile 末尾加 `RUN ldconfig` —— 修复了**另一个独立的** amd64 base
  问题（某些库未进缓存），但**修不好** arm64 base。
- 动态生成的 `zz-ngc-extra.conf` 重注册所有 HPC-X 库路径 —— 无关：NVIDIA 自己的
  `hpcx.conf` 已经注册了。问题出在库本身，不在注册。

## 3. 为什么 Tier 2 镜像"恰好"是好的

dev / runtime 两个 Tier 2 Dockerfile 都调用了 `ros2.sh`：

```bash
apt-get -y install ros-${ROS_DISTRO_VAL}-${ROS_TARGET_VAL}
apt-get -y install ros-dev-tools
```

ROS 2 的传递 apt 依赖拉进了系统 ports 版本的 `libucs`，装在
`/usr/lib/aarch64-linux-gnu/` 下。由于系统 lib 路径在 ld.so.conf 里比 NVIDIA 的
`hpcx.conf` 靠前，动态链接器优先使用它。在某些 ROS 2 release 里，那份系统
`libucs` **够新**，本身含 `ucs_config_doc_nop`，而 HPC-X 自带的 libucs 不含——
于是在 Tier 2 arm64 上导入 torch "恰好"能过。而在 base 上 ROS 2 未装 → 无系统
libucs 备胎 → torch 失败。

不要依赖这个侥幸。两个存活的 arm64 情况都是偶然；升 ROS 2 或在镜像中去掉
ROS 2 都会立即重现问题。

## 4. 修复：从 ld.so 中剔除 HPC-X libucc/libucx 注册 —— **仅 arm64**

最干净的修法：在 arm64 上就让 torch 看不到 HPC-X 那套坏了的 libucc/libucx。它们不在 torch 的
RPATH 中；torch 只是"不慎"看到了而已，是因为 `/etc/ld.so.conf.d/hpcx.conf`
（NVIDIA 提供）把 `/opt/hpcx/ucc/lib` 与 `/opt/hpcx/ucx/lib` 注册进了全局搜索路径。

**关键**：这条剔除**必须按架构 gate**。amd64 上 HPC-X 的 UCX/UCC 内部一致，**而且 torch 真的就 dlopen
libucc.so.1**——如果 amd64 上也剔除注册，torch 会崩 `libucc.so.1: cannot open shared object file: No such file or
directory`。剔除只针对 arm64。

在 `src/luciole-cuda-base/Dockerfile` 里，所有安装脚本之后的最后一条 `RUN`：

- 通过 `dpkg --print-architecture` 检测当前架构，
- 若 arm64：执行 `sed -i -E '\@^/opt/hpcx/(ucc|ucx)/lib$@d' hpcx.conf`
  **只删那两行**（其他 4 行 HPC-X 注册行保留），
- 若 amd64：`hpcx.conf` 完全不动，
- 然后两个架构都执行一次 `ldconfig`。

```dockerfile
RUN set -e; \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        sed -i -E '\@^/opt/hpcx/(ucc|ucx)/lib$@d' /etc/ld.so.conf.d/hpcx.conf; \
    fi; \
    ldconfig
```

### 为什么这个修复是对的

- arm64 上 torch 不再从 `/opt/hpcx/ucc/lib` 解析 `libucc.so.1` → 搜索链里完全找不到 libucc，
  而镜像上唯一副本又是坏的，所以"找不到"反而是对的。
- amd64 上 HPC-X 注册和 torch 的 libucc link **都保持原样**（这正是为什么要按架构 gate）。
- arm64 上其他 HPC-X 用户（MPI worker）仍然运行时可用：他们会自己
  `source /opt/hpcx/.../hpcx-init.sh`，该脚本会 export 出完整的 HPC-X
  `LD_LIBRARY_PATH` —— 与 ld.so.conf.d 无关。
- arm64 上 HPC-X 的其他库（hcoll、ompi、sharp、nccl_rdma_sharp_plugin）仍然注册着
  —— 只剔除符号错配的那 2 个。

### 这条指令在哪些文件里

- `src/luciole-cuda-base/Dockerfile`：按架构 gate 的 sed 删 `hpcx.conf` 两行 +
  `ldconfig`，作为 base 构建最后一步——修正 arm64 base 独立使用时的原始故障，amd64 原样保留。
- `src/luciole-cuda-dev/Dockerfile`、`src/luciole-cuda-runtime/Dockerfile`：
  从 base 继承（修正后的）`hpcx.conf`；各自末尾再跑一次 `RUN ldconfig` 作为安全网，让
  `ros2.sh`、`clang.sh`、（仅 dev）`devshell.sh` 引入的新 `.so` 也进缓存。
  arm64 上它们也不会重新加回 `hpcx/ucc/lib` 或 `hpcx/ucx/lib`。

## 5. 验证

修完后，上面矩阵六个格子的 smoke 测试全部通过：

- `src/_tests/smoke-base.sh` 在两种架构上都跑 `python3 -c "import torch"`。
- `src/_tests/smoke-runtime.sh`、`src/_tests/smoke-dev.sh` 也间接测 torch。

未来回归能被捕捉，是因为 smoke 测试**直接在原生 arch runner 上**跑发布的镜像，
**不加** `--privileged`、**不动** `LD_LIBRARY_PATH`——任何 dlopen 失败都会和真实用户
拉镜像时的表现完全一致。（我们**刻意没有**去 patch `LD_LIBRARY_PATH`——那样会把
bug 对没 source 对应 `profile.d` 脚本的用户隐藏掉。）

## 6. 推广：以后 CUDA/ML 镜像遇到 "undefined symbol" 怎么办

本文要传递的心智模型：以后 torch 或其他 ML import 在 CUDA 容器里报
`undefined symbol: <某符号>` 时，按这个清单走：

1. **提供该符号的 `.so` 到底有没有被注册进 ld.so.conf.d？**
   `find /opt -name '*.so*' | xargs dirname | sort -u` 与
   `ldconfig -p | grep -E '<库名>'` 对比，差异 = 路径没注册 → 补上。
2. **装该 `.so` 的那一步之后有没有跑 ldconfig？**
   每条装共享库的 `RUN` 都应当以 `ldconfig` 收尾（或被 Dockerfile 末尾的
   `RUN ldconfig` 覆盖）。
3. **是不是同库存在两份（系统 apt 版 vs. NVIDIA 自带版）？**
   如果 `ldconfig -p | grep libucc` 出现两条，dlopen 时第一条赢；修法通常是
   删掉重复的那份，或保证你想要的那份在 conf 排序里更靠前（小写字母前缀
   < `zz-`）。

容器基础镜像圈把这类问题叫"<某厂商镜像>漏注册 ld.so.conf 条目"bug；厂商立场
（含 NVIDIA）是应当由他们自己附 conf，但实践中每个 DKUAV 式的加固镜像总得
自己做一次这种发现与补注册。

## 7. 变更日志

- 2026-06-19 — 三个 Dockerfile 末尾都加了 `RUN ldconfig`。修了 amd64 base
  的 torch import。**没修好** arm64 base。
- 2026-06-22 (a) — 在 `luciole-cuda-base/Dockerfile` 把裸 `ldconfig` 换成
  动态写 `zz-ngc-extra.conf` + `ldconfig`。**仍没修好** arm64 base。
- 2026-06-22 (b) — 在原生 arm64 GH runner 上跑过
  `.github/workflows/diag-arm64-torch.yml` 诊断工作流，拉 `ghcr.io/dkuav/luciole-cuda-base:latest`。dump 揭示了**真正**根因：NVIDIA HPC-X v2.20 arm64
  把 UCX 1.17 与 UCC 1.4 打包在一起——符号不匹配（`ucs_config_doc_nop`）。
  随后的修复是：从 `hpcx.conf` 中去掉 `/opt/hpcx/{ucc,ucx}/lib` 两行，并保证它们不进入 `zz-ngc-extra.conf`。Tier 2 镜像末尾的 `ldconfig` 保留作为安全网。
- 2026-06-23 — **把该剔除按架构 gate**。上一版在两个架构上都从 `hpcx.conf` 剔除
  `/opt/hpcx/{ucc,ucx}/lib`，这破坏了 amd64：amd64 上 torch 的确从那里 dlopen
  `libucc.so.1`，剔除后链接器报 `libucc.so.1: cannot open shared object file: No
  such file or directory`。现在 sed 只在 `dpkg --print-architecture = arm64` 时跑，amd64
  完全不动。同时去掉了 `zz-ngc-extra.conf` 写入器——针对性的 sed 已经够用，没必要再维护一个发现式 conf。
- 2026-06-23 (b) — **CI 把 base 的 smoke 改为 advisory**。即使按架构 gate 了，arm64
  base 的 `import torch` 在 HPC-X 版本错配上仍然失败。预期修复点：升级上游 NVIDIA NGC
  pytorch 基础镜像。`src/_tests/smoke-base.sh` 仍然跑（每次构建 ✓/✗ 日志可见，作为
  回归诊断有用），只是失败不再挂 pipeline。CI gate（`.github/workflows/publish-images.yml`
  的 `SMOKE_ADVISORY_IMAGES` 集合）将 `luciole-cuda-base` 标为 advisory；Tier 2 镜像仍
  hard gate。修复后从该集合中去掉 `luciole-cuda-base` 即可恢复硬门禁。
