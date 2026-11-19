#!/bin/bash
# Check the inference server dependencies without NPU devices or a MinIO server.
# Sourced after _lib.sh by tools.images test.
set -uo pipefail

# shellcheck disable=SC1091
source /etc/profile.d/ascend-dev.sh

header "Inference server packages and inherited PEFT versions"
assert_cmd "Python package check" ascend-pip-check
assert_cmd "Inherited PEFT package versions are preserved" python3 -c '
from importlib.metadata import version
from pathlib import Path

for line in Path("/opt/image-python/infer-server-constraints.txt").read_text(encoding="utf-8").splitlines():
    package, expected = line.split("==", 1)
    actual = version(package)
    assert actual == expected, f"{package}: expected {expected}, got {actual}"
for package in ("flask", "flask-cors", "minio", "aclruntime", "ais-bench"):
    print(f"{package}=={version(package)}")
'
assert_cmd "Flask CLI" python3 -m flask --version
assert_cmd "Flask handles a cross-origin JSON request" python3 -c '
from flask import Flask
from flask_cors import CORS

app = Flask("infer-server-smoke")
CORS(app)
app.add_url_rule("/health", view_func=lambda: {"status": "ok"})
origin = "https://example.test"
with app.test_client() as client:
    response = client.get("/health", headers={"Origin": origin})
    assert response.status_code == 200
    assert response.json == {"status": "ok"}
    assert response.headers["Access-Control-Allow-Origin"] == origin
'
assert_cmd "MinIO client initializes without network access" python3 -c '
from minio import Minio

client = Minio("localhost:9000", secure=False)
assert callable(client.get_object) and callable(client.put_object)
'
assert_cmd "AIS Bench CLI loads the ACL runtime" python3 -m ais_bench --help

header "ONNX tools and MindStudio Probe"
assert_cmd "ONNX environment dependencies are consistent" uv pip check --python /opt/onnx/bin/python
assert_cmd "MindStudio Probe CLI starts" /opt/onnx/bin/msprobe --help
assert_cmd "ONNX tools load and ONNX Runtime runs a model on CPU" /opt/onnx/bin/python -c '
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

smoke_summary
