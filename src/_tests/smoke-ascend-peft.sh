#!/bin/bash
# Check PEFT packages and CPU model visualization without host NPU devices.
# Sourced after _lib.sh by tools.images test.
set -uo pipefail

# shellcheck disable=SC1091
source /etc/profile.d/ascend-dev.sh

header "PEFT packages and parent constraints"
assert_cmd "ARM64 host" test "$(uname -m)" = aarch64
assert_cmd "Python package check" ascend-pip-check
assert_cmd "PEFT metadata and unchanged vendor Torch" python3 -c '
from importlib.metadata import version
from pathlib import Path

base_versions = {}
for line in Path("/opt/image-python/base-constraints.txt").read_text(encoding="utf-8").splitlines():
    name, pinned_version = line.split("==", 1)
    base_versions[name.lower().replace("_", "-")] = pinned_version

for package in ("torch", "torch-npu"):
    expected = base_versions[package]
    actual = version(package)
    assert actual == expected, f"{package}: expected parent version {expected}, got {actual}"
for package in ("accelerate", "huggingface-hub", "peft", "transformers", "torchvision", "graphviz", "torchview"):
    print(f"{package}=={version(package)}")
'

header "Model visualization"
assert_cmd "Graphviz system tool" dot -V
assert_cmd "Graphviz renders SVG" python3 -c 'import graphviz; assert b"<svg" in graphviz.Digraph().pipe(format="svg")'
assert_cmd "torchview renders a CPU model" python3 -c '
import torch
from torchview import draw_graph

model = torch.nn.Sequential(torch.nn.Linear(4, 2), torch.nn.ReLU())
graph = draw_graph(model, input_size=(1, 4), device="cpu", graph_name="peft-smoke")
assert b"<svg" in graph.visual_graph.pipe(format="svg")
'

smoke_summary
