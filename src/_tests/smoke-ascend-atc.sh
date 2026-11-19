#!/bin/bash
# Exercise CANN conversion and AMCT calibration without an NPU.

compile_onnx() {
    atc --model="$1" --framework=5 --output="$2" --soc_version=Ascend910B2 \
        --input_shape='x:1,16,8,8' && test -s "$2.om"
}

ascend_atc_smoke() (
    work=$(mktemp -d) || exit 1
    trap 'rm -rf -- "$work"' EXIT
    cd "$work" && mkdir calibration || exit 1

    /opt/amct/bin/python -E - <<'PY' || exit 1
import amct_onnx
import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

assert amct_onnx.AMCT_SO is not None, "AMCT custom operators could not be loaded"
shape = [1, 16, 8, 8]
rng = np.random.default_rng(42)
weights = rng.normal(0, 0.2, (16, 16, 3, 3)).astype(np.float32)
graph = helper.make_graph(
    [helper.make_node("Conv", ["x", "weights"], ["y"], name="conv", pads=[1] * 4)],
    "smoke",
    [helper.make_tensor_value_info("x", TensorProto.FLOAT, shape)],
    [helper.make_tensor_value_info("y", TensorProto.FLOAT, shape)],
    [numpy_helper.from_array(weights, "weights")],
)
model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
onnx.checker.check_model(model)
onnx.save(model, "model.onnx")
rng.normal(size=shape).astype("<f4").tofile("calibration/000.bin")
PY

    compile_onnx model.onnx baseline || exit 1
    amct_onnx calibration --model model.onnx --save_path int8 \
        --input_shape 'x:1,16,8,8' --data_dir calibration --data_types float32 \
        --calibration_config /opt/ascend-atc/calibration.cfg || exit 1
    test -s int8_fake_quant_model.onnx || exit 1
    /opt/amct/bin/python -E -c 'import onnx; assert any(
        node.op_type == "AscendQuant"
        for node in onnx.load("int8_deploy_model.onnx").graph.node
    ), "AMCT deploy graph has no AscendQuant node"' || exit 1
    compile_onnx int8_deploy_model.onnx int8
)

header "CANN 8.5.0 conversion and CPU calibration"
assert_cmd "AMCT ACL library is installed in the Toolkit" \
    test -s "${ASCEND_TOOLKIT_HOME}/lib64/libamctacl.so"
assert_cmd "Compile baseline OM, calibrate with AMCT and compile INT8 OM" ascend_atc_smoke

header "OM inference and benchmarking"
assert_cmd "AIS Bench CLI loads the ACL runtime" python3.11 -m ais_bench --help

smoke_summary
