# Ascend ATC and AMCT ONNX

[中文文档](README_zh.md)

`ascend-atc` uses Huawei's CANN `8.5.0-910b-ubuntu22.04-py3.11` image on Linux ARM64. ATC compiles ONNX to OM. AMCT ONNX 0.23.2 calibrates INT8 models on the CPU using ONNX 1.14.0, ONNX Runtime 1.16.0 and the matching AMCT custom operators. The container starts in `/work` with CANN loaded. [AMCT 8.5.0 compatibility](https://www.hiascend.com/doc_center/source/en/CANNCommunityEdition/850/devaids/amct/atlasamct_16_0017.html)

ATC uses the vendor Python 3.11 with the CANN compiler dependencies installed. AMCT ONNX uses its own environment at `/opt/amct`. [CANN compiler dependencies](https://www.hiascend.com/doc_center/source/en/CANNCommunityEdition/850/softwareinst/instg/instg_0054.html)

## Build and run

Build from the repository root on an online ARM64 Docker host. For the repository's required smoke test, follow the [manifest build workflow](../../README.md#local-build-and-smoke-tests) with target `ascend-atc/8.5.0-910b-ubuntu22.04-py3.11` and platform `linux/arm64`. The smoke test checks that the AMCT ACL library is installed, then uses a small convolution model to exercise CPU calibration and both OM outputs for `Ascend910B2` without an NPU.

```bash
IMAGE=ascend-atc:8.5.0-910b-ubuntu22.04-py3.11
docker build --platform linux/arm64 -f src/ascend-atc/Dockerfile -t "$IMAGE" .
mkdir -p work
# Place model.onnx and any external weight files in work/.
docker run --pull=never --rm -it --network=none \
  --mount "type=bind,source=$PWD/work,target=/work" "$IMAGE"
```

To move the image to an offline ARM64 host, export it with `docker save -o ascend-atc.tar "$IMAGE"` and import it there with `docker load -i ascend-atc.tar`. The same `docker run` command works with the loaded image. Mount a writable workspace for models, calibration samples, logs and output files.

## Convert a floating-point baseline

Run the following commands in the container. Set `SOC` to the actual target's ATC SoC identifier and set `INPUT_SHAPE` to the model's fixed input names and dimensions. The example targets `Ascend910B2` with a single FP32 tensor in NCHW order. [ATC 8.5.0 SoC options](https://www.hiascend.com/doc_center/source/en/CANNCommunityEdition/850/devaids/atctool/atlasatcparam_16_0036.html)

```bash
SOC=Ascend910B2
INPUT_SHAPE='images:1,3,640,640'
mkdir -p output
atc --framework=5 --model=model.onnx --output=output/model-fp \
  --soc_version="$SOC" --input_shape="$INPUT_SHAPE"
```

## Calibrate INT8 and compile the deploy model

Export representative batches with the model's actual preprocessing, input dtype and layout. For the example above, put each contiguous little-endian FP32 input batch in a separate raw `.bin` file under `calibration/images/`. If the preprocessed batch is stored as a `.npy` file, use `np.ascontiguousarray(np.load(path), dtype="<f4").tofile(output_path)` to write the raw tensor. For multiple inputs, use one directory per input and the same zero-padded batch filenames in each directory. Separate input names and shapes, directory paths and dtypes with semicolons in their respective AMCT options, in matching order.

Copy the [calibration template](calibration.cfg) and set `batch_num` to the number of batches AMCT should read. AMCT sorts filenames lexicographically. Use `skip_layers` with the ONNX node name when you need to keep a layer in floating point. [AMCT ONNX calibration options](https://www.hiascend.com/document/detail/en/canncommercial/850/devaids/amct/atlasamct_16_0337.html)

```bash
cp /opt/ascend-atc/calibration.cfg quant.cfg
# Edit quant.cfg for the actual calibration set before running AMCT.
amct_onnx calibration --model=model.onnx --save_path=output/model-int8 \
  --input_shape="$INPUT_SHAPE" --data_dir=calibration/images \
  --data_types=float32 --calibration_config=quant.cfg &&
atc --framework=5 --model=output/model-int8_deploy_model.onnx \
  --output=output/model-int8 --soc_version="$SOC" --input_shape="$INPUT_SHAPE"
```

AMCT also writes `output/model-int8_fake_quant_model.onnx` for CPU accuracy simulation with the AMCT operators. ATC consumes the deploy ONNX and writes `output/model-int8.om`. Keep the calibration configuration and compare the baseline and INT8 OM on the Ascend910B2 with a held-out dataset. For a 310-series board, identify its full SoC, choose a build environment with compatible CANN and the corresponding ops package, and test the OM on that board.

The image also installs AMCT ACL 8.5.0 into the Toolkit. ATC inline calibration via the `calibration` block in `--compression_optimize_conf` requires a compatible NPU exposed to the container and an ATC compression configuration file. [ATC compression configuration](https://www.hiascend.com/doc_center/source/en/canncommercial/850/devaids/atctool/atlasatcparam_16_0059.html)
