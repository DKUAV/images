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
for package in ("accelerate", "huggingface-hub", "peft", "transformers", "torchvision", "graphviz", "torchview", "openai"):
    print(f"{package}=={version(package)}")
'

header "TorchVision CPU operators"
assert_import "TorchVision imports" torchvision
assert_cmd "TorchVision CPU NMS" python3 -c '
import torch
from torchvision.ops import nms

boxes = torch.tensor([[0., 0., 10., 10.], [1., 1., 9., 9.], [20., 20., 30., 30.]])
scores = torch.tensor([0.9, 0.8, 0.7])
assert nms(boxes, scores, 0.5).tolist() == [0, 2]
'

header "Python packaging and editable installs"
assert_import "OpenAI SDK imports" openai
assert_cmd "pip uses the vendor Python environment" python3 -c '
import subprocess
import sys

expected = subprocess.check_output([sys.executable, "-m", "pip", "--version"], text=True)
actual = subprocess.check_output(["pip", "--version"], text=True)
print(f"Python: {sys.executable}\npip: {actual.strip()}", flush=True)
assert actual == expected, f"pip environment differs: {actual!r} != {expected!r}"
'
assert_cmd "setuptools metadata and imported version agree" python3 -c '
from importlib.metadata import version
import setuptools

metadata_version = version("setuptools")
print(f"setuptools metadata: {metadata_version}")
print(f"setuptools import: {setuptools.__version__} from {setuptools.__file__}")
assert setuptools.__version__ == metadata_version
'
for backend in setuptools hatch-vcs; do
    for build_mode in isolated no-build-isolation; do
        assert_cmd "${backend} editable install (${build_mode})" python3 - "${build_mode}" "${backend}" <<'PYTHON'
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

with TemporaryDirectory(prefix="ascend-editable-smoke-") as temporary:
    root = Path(temporary)
    project = root / "project"
    project.mkdir()
    if sys.argv[2] == "hatch-vcs":
        configuration = (
            '[build-system]\nrequires = ["hatchling", "hatch-vcs"]\n'
            'build-backend = "hatchling.build"\n\n'
            '[project]\nname = "ascend-editable-smoke"\ndynamic = ["version"]\n'
            '[tool.hatch.build.targets.wheel]\npackages = ["src/ascend_editable_smoke"]\n'
            '[tool.hatch.version]\nsource = "vcs"\nfallback-version = "0.0.0"\n'
            '[tool.hatch.build.hooks.vcs]\nversion-file = "src/ascend_editable_smoke/_version.py"\n'
        )
    else:
        configuration = (
            '[build-system]\nrequires = ["setuptools>=64", "wheel"]\n'
            'build-backend = "setuptools.build_meta"\n\n'
            '[project]\nname = "ascend-editable-smoke"\nversion = "0.0.0"\n'
            '[tool.setuptools.packages.find]\nwhere = ["src"]\n'
        )
    (project / "pyproject.toml").write_text(configuration, encoding="utf-8")
    package = project / "src/ascend_editable_smoke"
    package.mkdir(parents=True)
    module = package / "__init__.py"
    module.write_text("VALUE = 1\n", encoding="utf-8")
    command = [sys.executable, "-m", "pip", "install", "--no-deps", "--editable", "."]
    if sys.argv[1] == "no-build-isolation":
        command.extend(["--no-build-isolation", "--no-index"])
    try:
        subprocess.run(command, cwd=project, check=True)
        if sys.argv[2] == "hatch-vcs":
            assert (package / "_version.py").is_file()
            subprocess.run(
                [sys.executable, "-c", "from ascend_editable_smoke._version import __version__; from importlib.metadata import version; assert __version__ == version(\"ascend-editable-smoke\")"],
                cwd=root,
                check=True,
            )
        for value in (1, 200):
            module.write_text(f"VALUE = {value}\n", encoding="utf-8")
            subprocess.run(
                [sys.executable, "-c", f"import ascend_editable_smoke as m; assert m.VALUE == {value}"],
                cwd=root,
                check=True,
            )
    finally:
        subprocess.run(
            [sys.executable, "-m", "pip", "uninstall", "--yes", "ascend-editable-smoke"],
            cwd=root,
            check=True,
        )
PYTHON
    done
done

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
