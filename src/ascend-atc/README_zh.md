# 昇腾 ATC 和 AMCT ONNX

[English documentation](README.md)

`ascend-atc` 基于华为的 CANN `8.5.0-910b-ubuntu22.04-py3.11` 镜像，运行于 Linux ARM64。ATC 将 ONNX 编译为 OM。AMCT ONNX 0.23.2 使用 ONNX 1.14.0、ONNX Runtime 1.16.0 和配套的 AMCT 自定义算子，在 CPU 上完成 INT8 校准。容器启动后位于 `/work`，并已加载 CANN 环境。 [AMCT 8.5.0 版本配套表](https://www.hiascend.com/doc_center/source/en/CANNCommunityEdition/850/devaids/amct/atlasamct_16_0017.html)

ATC 使用原厂 Python 3.11，依赖按 CANN 文档和软件包元数据安装。`amct_onnx` 命令使用 `/opt/amct` 下的独立环境，并忽略 Toolkit 的 Python 模块搜索路径。 [CANN 编译依赖](https://www.hiascend.com/doc_center/source/en/CANNCommunityEdition/850/softwareinst/instg/instg_0054.html)

## 构建和运行

在联网的 ARM64 Docker 宿主机上，从仓库根目录构建。若要执行仓库的必过烟测，按[清单构建流程](../../README_zh.md#本地构建与烟测)操作，使用目标 `ascend-atc/8.5.0-910b-ubuntu22.04-py3.11` 和平台 `linux/arm64`。烟测会检查 AMCT ACL 库是否已安装，再用小型卷积模型在无 NPU 环境下验证 CPU 校准和 `Ascend910B2` 的两份 OM 产物。

```bash
IMAGE=ascend-atc:8.5.0-910b-ubuntu22.04-py3.11
docker build --platform linux/arm64 -f src/ascend-atc/Dockerfile -t "$IMAGE" .
mkdir -p work
# Place model.onnx and any external weight files in work/.
docker run --pull=never --rm -it --network=none -e SSH_MODE=disabled \
  --mount "type=bind,source=$PWD/work,target=/work" "$IMAGE"
```

如需转移到离线 ARM64 主机，使用 `docker save -o ascend-atc.tar "$IMAGE"` 导出，在离线端用 `docker load -i ascend-atc.tar` 导入，再执行同一个 `docker run` 命令。挂载可写工作目录以保存模型、校准样本、日志和产物。

## 开发工具

镜像与 `luciole-ascend` 共用系统开发工具和交互 shell 安装脚本，包含 zsh 和 oh-my-zsh、Neovim 和 NvChad、tmux、ripgrep、clangd、fzf、eza、Starship、Sheldon、zoxide、Witr 和 micromamba。可通过 `/opt/dev-tools/bin/uv` 和 `/opt/dev-tools/bin/ty` 直接调用独立环境中的工具。

厂商 Python 3.11 和 `/opt/amct`、`/opt/onnx`、`/opt/dev-tools` 均安装 [Python 开发和打包工具](../_assets/ascend-python-dev-requirements.txt)、`opencv-contrib-python`、`scikit-image` 和 `h5py`。厂商 Python 还提供 IPython、pandas、Polars、matplotlib、Seaborn 和 Excel 读取等数据与交互工具。每套环境按自己的版本约束解析依赖。 [厂商 Python 依赖](atc-requirements.txt)

默认命令是 Bash。要使用交互式 zsh，可以保留原厂 CANN 环境与相同的工作目录挂载。

```bash
docker run --pull=never --rm -it --network=none -e SSH_MODE=disabled \
  --mount "type=bind,source=$PWD/work,target=/work" "$IMAGE" zsh -l
```

必过烟测会启动开发工具，检查四套环境的 Python 工具，并确认新开的 zsh 能找到 ATC、AMCT ACL 和厂商 Python 3.11。

## SSH 登录

容器入口先加载 CANN，再以默认的 `key-only` 模式启动 SSH。启动容器前，给 `root` 挂载非空的 `authorized_keys`。目录和文件的所有者都应为 root，权限分别为 `0700` 和 `0600`。以下示例将 SSH 端口映射到宿主机的回环地址。

```bash
sudo install -d -m 0700 "$PWD/ssh"
sudo install -m 0600 "$HOME/.ssh/id_ed25519.pub" "$PWD/ssh/authorized_keys"
docker run --pull=never --rm -d -p 127.0.0.1:2222:22 \
  --mount "type=bind,source=$PWD/ssh,target=/root/.ssh,readonly" \
  --mount "type=bind,source=$PWD/work,target=/work" "$IMAGE" sleep infinity
ssh -p 2222 root@127.0.0.1
```

直接运行本地命令或用 `--network=none` 离线运行时，设置 `SSH_MODE=disabled`。烟测会确认默认启动需要公钥，并实际用公钥登录，再从 SSH 会话验证 CANN。

## 编译浮点基线

在容器内执行以下命令。将 `SOC` 设为实际目标设备的 ATC SoC 标识，将 `INPUT_SHAPE` 设为模型的固定输入名和维度。示例使用 `Ascend910B2` 和单路 NCHW FP32 张量。 [ATC 8.5.0 SoC 参数](https://www.hiascend.com/doc_center/source/en/CANNCommunityEdition/850/devaids/atctool/atlasatcparam_16_0036.html)

```bash
SOC=Ascend910B2
INPUT_SHAPE='images:1,3,640,640'
mkdir -p output
atc --framework=5 --model=model.onnx --output=output/model-fp \
  --soc_version="$SOC" --input_shape="$INPUT_SHAPE"
```

## INT8 校准与编译

按实际模型的预处理、输入 dtype 和布局导出有代表性的批次。以上例为准，每个连续的小端 FP32 输入 batch 保存为一个原始 `.bin`，并放入 `calibration/images/`。若预处理后的批次保存在 `.npy` 文件中，可用 `np.ascontiguousarray(np.load(path), dtype="<f4").tofile(output_path)` 写出原始张量。多输入模型按输入分别建目录，同批次在各目录中使用相同的补零文件名。AMCT 的输入名称和形状、数据目录、dtype 各自在对应参数中用分号分隔，顺序保持一致。

复制[校准配置模板](calibration.cfg)，将 `batch_num` 改为 AMCT 要读取的批次数。AMCT 按文件名字典序读取。若某层需要保留浮点，可把 ONNX 节点名填入 `skip_layers`。 [AMCT ONNX 校准参数](https://www.hiascend.com/document/detail/en/canncommercial/850/devaids/amct/atlasamct_16_0337.html)

```bash
cp /opt/ascend-atc/calibration.cfg quant.cfg
# Edit quant.cfg for the actual calibration set before running AMCT.
amct_onnx calibration --model=model.onnx --save_path=output/model-int8 \
  --input_shape="$INPUT_SHAPE" --data_dir=calibration/images \
  --data_types=float32 --calibration_config=quant.cfg &&
atc --framework=5 --model=output/model-int8_deploy_model.onnx \
  --output=output/model-int8 --soc_version="$SOC" --input_shape="$INPUT_SHAPE"
```

AMCT 还会生成 `output/model-int8_fake_quant_model.onnx`，供 CPU 使用 AMCT 算子做精度仿真。ATC 读取部署用 ONNX，生成 `output/model-int8.om`。保留校准配置，在 Ascend910B2 上用独立的验证集对比浮点和 INT8 OM。若后续要为 310 系列设备编译，先确认完整 SoC 标识，选择含兼容 CANN 和对应算子包的构建环境，再在目标板上验收 OM。

镜像也在 Toolkit 中安装 AMCT ACL 8.5.0。若要通过 `--compression_optimize_conf` 的 `calibration` 段执行 ATC 内联校准，需要给容器挂载兼容的 NPU，并提供 ATC 压缩配置文件。 [ATC 压缩配置](https://www.hiascend.com/doc_center/source/en/canncommercial/850/devaids/atctool/atlasatcparam_16_0059.html)

## ONNX 工具与 MindStudio Probe

本镜像与 `luciole-ascend` 共用 [ONNX 依赖清单](../_assets/onnx-requirements.txt)，在 `/opt/onnx` 独立的 Python 3.11 环境中安装 ONNX、ONNX Runtime、ONNX Simplifier、ONNX Slim、ONNX Optimizer、ONNX GraphSurgeon、ONNX Converter Common、ONNX Script 和 MindStudio Probe。ARM64 构建在没有可用 wheel 时从源码编译 `onnxoptimizer`。

容器入口会加载厂商的 CANN `PYTHONPATH`。在容器内运行 ONNX 脚本时用 `-E` 忽略该环境变量，运行 CLI 时可以只对当前命令清除它。

```bash
/opt/onnx/bin/python -E -c 'import onnx; print(onnx.__version__)'
env -u PYTHONPATH /opt/onnx/bin/onnxsim model.onnx model-simplified.onnx
env -u PYTHONPATH /opt/onnx/bin/msprobe --help
```

ONNX Runtime 使用 CPU 执行提供程序。这个环境中的 MindStudio Probe 用于离线分析。必过烟测会检查环境依赖、启动 msProbe CLI，并优化一个小型 ONNX 模型后在 CPU 上执行。

## OM 推理与基准测试

[ATC 依赖](atc-requirements.txt)通过 SHA256 固定官方 `ais-bench` 和 `aclruntime` 0.0.2 wheel。AIS Bench 使用厂商 Python 3.11，`aclruntime` 使用对应的 ARM64 CPython 3.11 wheel。必过烟测运行 `python3.11 -m ais_bench --help`，检查 CLI 能否加载原生 runtime。 [Ascend AIS Bench 推理工具指南](https://gitee.com/ascend/tools/blob/master/ais-bench_workload/tool/ais_bench/README.md)

在已注册 Ascend Docker Runtime 且驱动与 CANN 8.5.0 兼容的 ARM64 主机上，从仓库根目录对上面生成的模型进行基准测试：

```bash
docker run --pull=never --rm --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled \
  --mount "type=bind,source=$PWD/work,target=/work" "$IMAGE" \
  python3.11 -m ais_bench --model /work/output/model-int8.om --device 0
```
