#!/bin/bash
# Exercise the shared ONNX tools with the CANN Python path excluded.
assert_cmd "MindStudio Probe CLI starts" env -u PYTHONPATH /opt/onnx/bin/msprobe --help
assert_cmd "ONNX tools load and ONNX Runtime runs a model on CPU" /opt/onnx/bin/python -E -c '
from importlib import import_module
import sys

import numpy as np
import onnx
import onnxoptimizer
import onnxruntime
from onnx import TensorProto, helper

assert sys.prefix != sys.base_prefix
for module in ("onnxsim", "onnxslim", "onnx_graphsurgeon", "onnxconverter_common", "onnxscript"):
    import_module(module)

graph = helper.make_graph(
    [helper.make_node("Add", ["x", "x"], ["y"])],
    "onnx-smoke",
    [helper.make_tensor_value_info("x", TensorProto.FLOAT, [1])],
    [helper.make_tensor_value_info("y", TensorProto.FLOAT, [1])],
)
model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)], ir_version=8)
onnx.checker.check_model(model)
optimized = onnxoptimizer.optimize(model)
session = onnxruntime.InferenceSession(
    optimized.SerializeToString(), providers=["CPUExecutionProvider"]
)
result, = session.run(["y"], {"x": np.array([2.0], dtype=np.float32)})
np.testing.assert_array_equal(result, np.array([4.0], dtype=np.float32))
'
