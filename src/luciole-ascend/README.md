# Luciole Ascend development image

This ARM64 image builds on `ascendai/torch-npu:2.10.0.post7-cann9.2.0-910b-ubuntu22.04-py3.12` and publishes as `ghcr.io/dkuav/luciole-ascend`. The base tag is fixed, but its digest is deliberately not pinned. See the [Chinese guide](README_zh.md).

## Contents and build

The vendor base supplies Python 3.12, PyTorch 2.10.0, TorchNPU 2.10.0.post7 and CANN 9.2.0. Shared scripts install system tools, CMake 4.3.2, SSH and the development shell. The image retains the vendor root account and uses `/root` as HOME so root-owned CANN scripts remain readable. Both image families install the shared `vendor/image-kit/assets/python-dev-requirements.txt`, including uv, ty, Ruff, setuptools, setuptools-scm, Hatchling, hatch-vcs, editables, uv_build, wheel and packaging, through separate pip scripts. Ascend's script preserves the vendor Python environment with constraints generated from every preinstalled package and restores CANN in login shells and the entrypoint. CUDA-specific vision packages, ROS 2 and networking library steps are not included.

The shared developer tools include the Graphviz system executable. PEFT dependencies and the `graphviz` and `torchview` Python packages are installed in the derived [ascend-peft image](../ascend-peft/README.md).

The package check permits only three exact known vendor diagnostics: the `mindstudio-kl 26.2.0` NumPy bound and the two missing `ms-service-profiler 26.0.0` OTLP exporters. Other dependency errors fail the build. This does not establish compatibility for the affected vendor features. The image keeps upstream apt and pip sources.

Build and run smoke checks on a native ARM64 host:

```bash
python -m image_kit plan --target luciole-ascend/2.10.0.post7-cann9.2.0-910b-ubuntu22.04-py3.12 --output build-plan.json
python -m image_kit bake --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64 --mode load --output docker-bake.load.json
docker buildx bake -f docker-bake.load.json
python -m image_kit test --plan build-plan.json --owner dkuav --revision "$(git rev-parse HEAD)" --platform linux/arm64
```

Direct builds use the tagged vendor base by default and the repository root as context. Compose only runs published images and has no `build` section; use the manifest/Bake commands above to build and test this checkout. CI publishes explicit variant and batch-qualified build tags after all native checks pass. The required smoke test needs no NPU and does not verify hardware compatibility.

## Micromamba

The image includes micromamba 2.10.0 for creating separate Conda environments. The manifest pins the release and its ARM64 checksum. Run `micromamba --version` to check the executable. See the [environment creation example](../luciole-cuda-base/README.md#micromamba).

## Model compilation and deployment

### AMCT quantization

The image installs AMCT ACL 9.2.0 into the CANN Toolkit and AMCT ONNX 0.24.1 into an isolated Python 3.12 environment at `/opt/amct`. The `amct_onnx` command runs in that environment with ONNX 1.18.0, ONNX Runtime 1.20.0 and the matching custom operators. Its [requirements](amct-requirements.txt) resolve separately from `/opt/onnx` and the vendor Python environment. [AMCT ONNX compatibility](https://www.hiascend.com/doc_center/source/en/CANNCommunityEdition/910/devaids/amct/atlasamct_16_0014.html)

Run `amct_onnx calibration --help` for the CPU calibration command. Use representative input batches with the model's real preprocessing and layout. For example, place raw NCHW float32 batches in `calibration/images/` and adjust the sample shape and batch count below. Use an ONNX model with IR version 10 or earlier for ONNX Runtime 1.20. [ONNX Runtime compatibility](https://onnxruntime.ai/docs/reference/compatibility.html)

```bash
mkdir -p output
INPUT_SHAPE='images:1,3,640,640'
amct_onnx calibration --model=model.onnx --save_path=output/model-int8 \
  --input_shape="$INPUT_SHAPE" --data_dir=calibration/images \
  --data_types=float32 --batch_num=1 &&
atc --framework=5 --model=output/model-int8_deploy_model.onnx \
  --output=output/model-int8 --soc_version=Ascend910B2 --input_shape="$INPUT_SHAPE"
```

AMCT ACL supports ATC inline calibration through the `calibration` block in `--compression_optimize_conf`. Use a compatible NPU host and expose the device to the container for that path. The required container smoke test checks the installed ACL library, runs AMCT ONNX calibration on the CPU and compiles the deploy model into an INT8 OM for `Ascend910B2`. [ATC compression options](https://www.hiascend.com/document/detail/zh/CANNCommunityEdition/920beta1/devaids/atctool/docs/zh/user_guides/atc_tools/CLI_options/--compression_optimize_conf.md)

### ONNX tools and MindStudio Probe

The build uses `uv` to create a separate Python 3.12 environment at `/opt/onnx` with `onnx`, `onnxruntime`, `onnxsim`, `onnxslim`, `onnxoptimizer`, `onnx-graphsurgeon`, `onnxconverter-common`, `onnxscript`, and `mindstudio-probe>=26.2.0`. The [environment requirements](../_assets/onnx-requirements.txt) resolve independently of the default Python environment's vendor pins. The ARM64 build compiles `onnxoptimizer` from source when a wheel is unavailable.

Use `/opt/onnx/bin/python` for ONNX scripts and `/opt/onnx/bin/msprobe --help` to see the MindStudio Probe commands. Run `source /opt/onnx/bin/activate` in Bash to put both sets of tools on your shell's path. ONNX Runtime uses the CPU execution provider. Use this msProbe environment for offline analysis. In-process precision debugging requires msProbe, PyTorch, and TorchNPU in the same Python environment.

The required smoke test checks dependency consistency, runs `msprobe --help`, imports the eight ONNX packages and verifies an optimized graph with ONNX Runtime's CPU execution provider.

### OM inference and benchmarking

The [AIS Bench requirements](ais-bench-requirements.txt) pin the official `ais-bench` and `aclruntime` 0.0.2 wheels by SHA256. The `aclruntime` wheel targets Linux ARM64 and CPython 3.12. Both packages use the vendor Python with its existing dependency constraints. The required smoke test runs `python3 -m ais_bench --help` to check that the CLI loads the native ACL runtime. [Ascend AIS Bench inference guide](https://gitee.com/ascend/tools/blob/master/ais-bench_workload/tool/ais_bench/README.md)

Inside an [NPU-enabled container](#running-with-an-npu), benchmark an OM model with `python3 -m ais_bench --model /work/model.om --device 0`.

## Running with an NPU

Use an ARM64 host with a compatible Ascend 910B driver and Ascend Docker Runtime. Follow the [vendor compatibility information](https://www.hiascend.com/developer/download/compatibility) for host driver and CANN pairing. For example, with the `ascend` runtime registered:

```bash
IMAGE=ghcr.io/dkuav/luciole-ascend:2.10.0.post7-cann9.2.0-910b-ubuntu22.04-py3.12
docker run --rm -it --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE"
docker run --rm -i --runtime=ascend -e ASCEND_VISIBLE_DEVICES=0 -e SSH_MODE=disabled "$IMAGE" bash -s < src/_tests/npu-ascend.sh
```

The default user is `root`, HOME is `/root`, the work directory is `/work`, and the default command is Bash; the login shell is zsh. The default SSH mode is `key-only`; mount a nonempty `/root/.ssh/authorized_keys` before startup. Password authentication is disabled in this mode. Set `SSH_MODE=disabled` when SSH is unnecessary. Explicit password mode remains available and requires a nonempty runtime-mounted file referenced by `SSH_PASSWORD_FILE`. Root SSH grants full container privileges; publish port 22 only on a trusted interface. No password is stored in image layers.

The Compose example selects `linux/arm64` and `runtime: ascend`, defaults `ASCEND_VISIBLE_DEVICES` to `0,1,2,3,4,5,6,7` when unset or empty, and allocates 8 GiB of shared memory. Override the list for hosts with fewer NPUs or to expose a subset (for example, `0` or `0,1`). The host Ascend runtime supplies the selected NPU devices and driver mounts. It mounts `src/luciole-ascend/mount/` at `/work`, runs `sleep infinity`, and restarts unless stopped. It also maps `host.docker.internal` to the host gateway and enables debugging with `SYS_PTRACE` and `seccomp:unconfined`.

It maps port `2222:22` and mounts an existing SSH configuration directory read-only at `/root/.ssh`. Set `SSH_CONFIG_DIR` to its host path before `docker compose up`; Compose fails if the variable is unset or the source directory is missing. The directory and its `authorized_keys` must be root-owned, with modes `0700` and `0600` respectively. Use a dedicated container directory and copy the client's public key into `authorized_keys`; private keys used to log into this container stay on the client. Empty keys are rejected by default. For example, from the repository root on a Linux host:

```bash
docker info --format '{{json .Runtimes}}'  # Confirm that ascend is registered.
sudo install -d -m 0700 /srv/luciole-ascend/ssh
sudo install -m 0600 ~/.ssh/id_ed25519.pub /srv/luciole-ascend/ssh/authorized_keys
export SSH_CONFIG_DIR=/srv/luciole-ascend/ssh
# Optional: export ASCEND_VISIBLE_DEVICES=0,1 to override the eight-NPU default.
docker compose -f src/luciole-ascend/docker-compose.yml pull
docker compose -f src/luciole-ascend/docker-compose.yml up -d
docker compose -f src/luciole-ascend/docker-compose.yml exec app npu-smi info
docker compose -f src/luciole-ascend/docker-compose.yml exec app zsh
```

The host directory survives image updates and container replacement. Edit it on the host; the read-only mount prevents changes from inside the container, including updates to SSH client `known_hosts`. Server identity keys live under `/etc/ssh/ssh_host_*`, outside this mount, so preserving the server fingerprint requires separate persistence. Hardware device mounts and runtime registration are host responsibilities.

SSH follows the explicitly selected `DEFAULT_USER`: selecting `root` permits key-only root access with a nonempty `/root/.ssh/authorized_keys` by default; root password access requires a nonempty mounted `SSH_PASSWORD_FILE`. Root SSH grants full container privileges. Changing `DEFAULT_USER` at runtime selects the SSH account, not the Dockerfile command user.

The shared system installer accepts `--timezone` and `--upgrade`; Dockerfiles pass both values explicitly. The manifest omits UID/GID and supplementary groups for root: the vendor account is neither recreated nor renumbered. Its smoke test starts through Bash, restores the installed vendor environment, and explicitly tests the real Ascend entrypoint and SSH credential policy.

Shared scripts and assets come from the commit-pinned `vendor/image-kit` submodule; Luciole extensions remain in `src/_scripts/` and `src/_assets/`. Manifests declare every copied input. Initialize the component with `git submodule update --init --recursive` before building.

The shared entrypoint is installed as `/usr/local/bin/docker-entrypoint`. Key-only mode requires nonempty `authorized_keys` by default. Explicit `SSH_ALLOW_EMPTY_AUTHORIZED_KEYS=true` allows sshd to start while waiting for a public key to be configured; an empty file does not enable unauthenticated login.

image-kit installs `gosu` and `sudo`; local `luciole-dev-tools.sh` adds `landscape-common`. CUDA dev/runtime inherit these tools from the base.

`SYSTEM_UPGRADE` remains `false`. Ascend preserves vendor Python/CANN constraints and does not run the CUDA psutil or vision-extension installation.

The manifest explicitly declares the shared smoke helper with `variants[].tests[].library`; the pinned image-kit package runs the build and smoke contract.

Publication uses YAML `name` independently of the directory and explicit variant channels. Verified build tags are `<variant>-<sha12>-<run-id>-<attempt>`; formal `<variant>-vMAJOR.MINOR.PATCH` tags promote an existing successful main publication receipt. All required native workers must pass before public tags advance. Historical tags remain available.
