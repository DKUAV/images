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

## 2. 根因：ld.so.cache 过期 + ld.so.conf 未注册

要触发这个失败需要两个独立条件同时成立，二者都源自 Docker 分层与
`ldconfig` 的交互机制：

### 2.1 ld.so.cache 按 Docker 层做快照

Dockerfile 里每一条 `RUN` 产生一层，该层文件系统快照里包含的 `/etc/ld.so.cache`
是 **该 RUN 结束时的状态**。后续 RUN 添加 `.so` 文件时，是在"已过期"的缓存之上
添加的——除非它们自己再跑一次 `ldconfig`。例如：`opencv.sh` 跑了 `ldconfig`，
之后 `pip-packages.sh` 又解出新 `.so`，那么这些新文件**不在**最终层看到的缓存中。

光这一点理论上加 `RUN ldconfig` 就能修；但本案例不够，因为还有条件 #2。

### 2.2 ldconfig 只扫 ld.so.conf 中声明过的路径

`ldconfig` **不会全盘扫描整个文件系统**。它只扫：

- `/usr/lib` 与 multiarch triplet（`/usr/lib/x86_64-linux-gnu`、
  `/usr/lib/aarch64-linux-gnu` 等）
- `/etc/ld.so.conf` include 的所有内容，也就是 `/etc/ld.so.conf.d/*.conf`
  里列出的路径

所以 **`RUN ldconfig` 的效果由 conf 文件决定。** 如果某个厂商把 `.so` 文件
放到一个没在任何 conf 行里声明过的目录下，`ldconfig` **永远是发现不了它**
的——你跑多少次都没用。

### 2.3 不对称：NVIDIA 在 amd64 预注册，arm64 没有

NVIDIA 的 NGC `pytorch:24.10-py3` 镜像把 HPC-X 栈（UCX、UCC、Sharp 等）
放在 `/opt/hpcx/`：

- 在 **amd64** 上，他们通过 `/etc/ld.so.conf.d/...` 文件预注册了每一个
  `lib` 子目录，`ldconfig` 就会扫到。
- 在 **aarch64 / Jetson L4T** 上，对应的 conf 条目在当前 NGC release 里
  **缺失**。`ldconfig` 没东西可扫，缓存对 HPC-X 一无所知。

这是 Jetson NGC 镜像的老问题，在"有人设 dlopen 进那条 .so 链"之前完全
看不见——而 `import torch` 就恰好是这么干的。

## 3. 为什么 Tier 2 镜像"恰好"是好的

dev / runtime 两个 Tier 2 Dockerfile 都调用了 `ros2.sh`：

```bash
apt-get -y install ros-${ROS_DISTRO_VAL}-${ROS_TARGET_VAL}
apt-get -y install ros-dev-tools
```

装 ROS 2 会拉入一大堆共享库 dpkg 包。**dpkg 在装任何含 `.so` 的包之后，
会作为 maintainer script trigger 跑 `ldconfig`。** 这个隐式 trigger 在
`apt-get install ros-…` 流程末尾跑了，效果是：

1. 把那一层的 ld.so.cache 刷了一次。
2. ROS 2 的传递依赖还顺带拉进了系统 ports 版本的 `libucc` / `libucs`
   （装在 `/usr/lib/aarch64-linux-gnu`，**这个 triplet 路径默认是注册的**）。
   它们在 dlopen 排序里比"缺失于缓存"的 `/opt/hpcx/...` 版本更靠前，于是
   dlopen 链巧合命中了一对自洽的版本。

base 镜像不跑 `ros2.sh`，两个副作用都没有。amd64 base 上，NVIDIA 自带的
ld.so.conf 条目覆盖了 HPC-X，所以仍工作；arm64 base 上谁都没有，于是挂。
矩阵汇总：

| 镜像        | amd64                                  | arm64                                                          |
|-------------|----------------------------------------|----------------------------------------------------------------|
| `luciole-cuda-base`     | ✓ — NVIDIA 预注册了 HPC-X         | ✗ — 没 ros2 trigger，也没 NVIDIA 注册 → torch 失败              |
| `luciole-cuda-dev`      | ✓ — 两个效果都覆盖                | ✓ — ros2.sh 的 dpkg trigger 恰好把缓存修好                     |
| `luciole-cuda-runtime`  | ✓ — 两个效果都覆盖                | ✓ — 同 dev                                                     |

两个存活的 arm64 情况都是**侥幸**，依赖的是 `ros-humble-ros-base` 这个具体
依赖图。换一版 ROS 2，或者在不 source ROS 2 的情况下用同一镜像，就会再挂。

## 4. 通用修复：动态发现 ld.so.conf + ldconfig

在 `src/luciole-cuda-base/Dockerfile`，所有安装脚本之后的最后一条 `RUN`
现在会写一个文件——`/etc/ld.so.conf.d/zz-ngc-extra.conf`，里面是
**NVIDIA /opt 厂商根与 `/usr/local/lib` 下所有真实含 `.so` 文件的目录**，
然后再跑 `ldconfig`：

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

### 为什么这样最稳

- **动态发现，而非硬编码列表**（`ucx/lib`、`ucc/lib`、`sharp/lib`……）。
  能扛住 HPC-X 内部路径改名、以及未来扔到 `/opt/<新东西>` 下的任何 NGC 包，
  不需要有人回头改这条 Dockerfile。
- `-type f -name '*.so*'` 只挑**真正含共享对象**的目录，避免把
  `/opt/nvidia` 里空 `lib/` 占位目录也注册进去污染 conf。
- `xargs -r dirname | sort -u` 输出"每行一个绝对路径、去重"，正是
  ld.so.conf.d 期望的格式。
- `zz-` 前缀让这个 conf 排在最后，将来 NVIDIA 或 Ubuntu 加他们自己的 conf
  时对同名 lib 优先于我们（我们不想 shadow 别人的）。
- `2>/dev/null` 让命令在顶层目录缺失（比如没有 `/opt/tensorrt`）时也容错。
- 与架构无关：在 amd64 镜像里 find 只出 amd64 的目录，在 arm64 镜像里只出
  arm64 的——因为它只列出**当下镜像里实际存在**的路径。

### 这条指令在哪些文件里

- `src/luciole-cuda-base/Dockerfile`：base 构建的最后一步写
  `zz-ngc-extra.conf` 并跑 `ldconfig` —— 修正 arm64 base 独立使用时的原始
  故障。
- `src/luciole-cuda-dev/Dockerfile`、`src/luciole-cuda-runtime/Dockerfile`：
  从 base 继承该 conf；它们各自末尾再跑一次 `RUN ldconfig` 作为安全网，
  让 `ros2.sh`、`clang.sh`、（仅 dev）`devshell.sh` 引入的新 `.so` 也落到
  缓存里。

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

- 2026-06-19 — 三个 Dockerfile 都加了 `RUN ldconfig`。修复了 amd64
  （`luciole-cuda-base`）的 torch import。**没修好** arm64 base。
- 2026-06-22 — 在 `luciole-cuda-base/Dockerfile` 把裸 `ldconfig` 替换为
  "动态发现写 `zz-ngc-extra.conf` + ldconfig"。自此修复了 arm64 base
  独立使用场景。Tier 2 镜像此前本就通过（侥幸），保留各自末尾的冗余
  `ldconfig` 作为安全网，并把自己引入的 `/opt/ros/...`（ros2.sh）、
  clang/devshell 的 `.so` 也注册进去。
