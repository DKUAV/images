#!/bin/bash
# Check PEFT packages and CPU model visualization without host NPU devices.
# Sourced after _lib.sh by tools.images test.
set -uo pipefail

# shellcheck disable=SC1091
source /etc/profile.d/ascend-dev.sh

header "PEFT packages and parent constraints"
assert_cmd "ARM64 host" test "$(uname -m)" = aarch64
assert_cmd "Python package check" ascend-pip-check
assert_cmd "PEFT metadata and protected parent packages" python3 -c '
from importlib.metadata import version
from pathlib import Path

base_versions = {}
for line in Path("/opt/image-python/base-constraints.txt").read_text(encoding="utf-8").splitlines():
    name, pinned_version = line.split("==", 1)
    base_versions[name.lower().replace("_", "-")] = pinned_version

auxiliary_versions = {
    "attrs": "24.2.0",
    "numpy": "1.26.4",
    "scipy": "1.13.1",
    "decorator": "5.1.1",
    "psutil": "6.0.0",
}
for package, expected in (base_versions | auxiliary_versions).items():
    actual = version(package)
    assert actual == expected, f"{package}: expected {expected}, got {actual}"
assert version("triton-ascend") == "3.6.0"
for package in ("accelerate", "huggingface-hub", "peft", "transformers", "torchvision", "graphviz", "torchview", "openai", "flash-linear-attention", "fla-core", "triton-ascend", "triton"):
    print(f"{package}=={version(package)}")
'

header "FLA and Triton Ascend without NPU devices"
assert_cmd "Triton Ascend backend loads" python3 -c '
import triton.backends
from triton._C import libtriton

assert "ascend" in triton.backends.backends
assert hasattr(libtriton, "ascend")
'
assert_cmd "FLA linear attention imports" python3 -c '
from fla.ops.linear_attn import chunk_linear_attn

assert callable(chunk_linear_attn)
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
for backend in setuptools setuptools-scm hatch-vcs uv_build; do
    for build_mode in isolated no-build-isolation; do
        assert_cmd "${backend} packaging (${build_mode})" python3 - "${build_mode}" "${backend}" <<'PYTHON'
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

with TemporaryDirectory(prefix="ascend-editable-smoke-") as temporary:
    root = Path(temporary)
    project = root / "project"
    project.mkdir()
    (project / "README.md").write_text("Packaging smoke fixture.\n", encoding="utf-8")
    if sys.argv[2] == "hatch-vcs":
        configuration = (
            '[build-system]\nrequires = ["hatchling", "hatch-vcs"]\n'
            'build-backend = "hatchling.build"\n\n'
            '[project]\nname = "ascend-editable-smoke"\ndynamic = ["version"]\n'
            '[tool.hatch.build.targets.wheel]\npackages = ["src/ascend_editable_smoke"]\n'
            '[tool.hatch.version]\nsource = "vcs"\nfallback-version = "0.0.0"\n'
            '[tool.hatch.build.hooks.vcs]\nversion-file = "src/ascend_editable_smoke/_version.py"\n'
        )
    elif sys.argv[2] == "setuptools-scm":
        configuration = (
            '[build-system]\nrequires = ["setuptools>=80", "setuptools-scm>=8"]\n'
            'build-backend = "setuptools.build_meta"\n\n'
            '[project]\nname = "ascend-editable-smoke"\ndynamic = ["version"]\n'
            '[tool.setuptools.packages.find]\nwhere = ["src"]\n'
            '[tool.setuptools_scm]\nfallback_version = "0.0.0"\n'
            'version_file = "src/ascend_editable_smoke/_version.py"\n'
        )
    elif sys.argv[2] == "uv_build":
        configuration = (
            '[build-system]\nrequires = ["uv_build"]\n'
            'build-backend = "uv_build"\n\n'
            '[project]\nname = "ascend-editable-smoke"\nversion = "1.2.3"\n'
        )
    else:
        configuration = (
            '[build-system]\nrequires = ["setuptools>=64", "wheel"]\n'
            'build-backend = "setuptools.build_meta"\n\n'
            '[project]\nname = "ascend-editable-smoke"\nversion = "1.2.3"\n'
            '[tool.setuptools.packages.find]\nwhere = ["src"]\n'
        )
    (project / "pyproject.toml").write_text(configuration, encoding="utf-8")
    package = project / "src/ascend_editable_smoke"
    package.mkdir(parents=True)
    module = package / "__init__.py"
    module.write_text("VALUE = 1\n", encoding="utf-8")
    vcs_backend = sys.argv[2] in ("hatch-vcs", "setuptools-scm")
    version_check = (
        "from ascend_editable_smoke._version import __version__; "
        "from importlib.metadata import version; "
        "assert __version__ == version(\"ascend-editable-smoke\") == \"1.2.3\""
    )
    if vcs_backend:
        (project / ".gitignore").write_text(
            "src/ascend_editable_smoke/_version.py\n__pycache__/\n*.egg-info/\nbuild/\n",
            encoding="utf-8",
        )
        for arguments in (
            ["init", "--quiet"],
            ["add", "."],
            ["-c", "user.name=Image smoke", "-c", "user.email=smoke@example.invalid",
             "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
             "commit", "--quiet", "-m", "Create packaging fixture"],
            ["-c", "tag.gpgsign=false", "tag", "v1.2.3"],
        ):
            subprocess.run(["git", *arguments], cwd=project, check=True)
    command = [sys.executable, "-m", "pip", "install", "--no-deps",
               "--check-build-dependencies", "--editable", "."]
    if sys.argv[1] == "no-build-isolation":
        command.extend(["--no-build-isolation", "--no-index"])
    try:
        subprocess.run(command, cwd=project, check=True)
        if vcs_backend:
            assert (package / "_version.py").is_file()
            subprocess.run(
                [sys.executable, "-c", version_check],
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
    if sys.argv[1] == "no-build-isolation":
        module.write_text("VALUE = 1\n", encoding="utf-8")
        environment = os.environ.copy()
        environment["PIP_NO_INDEX"] = "1"
        artifacts = root / "dist"
        subprocess.run(
            [sys.executable, "-m", "build", "--no-isolation", "--outdir", str(artifacts)],
            cwd=project,
            env=environment,
            check=True,
        )
        assert len(list(artifacts.glob("*.tar.gz"))) == 1
        wheels = list(artifacts.glob("*.whl"))
        assert len(wheels) == 1
        try:
            subprocess.run(
                [sys.executable, "-m", "pip", "install", "--no-index", "--no-deps", str(wheels[0])],
                cwd=root,
                check=True,
            )
            subprocess.run(
                [sys.executable, "-c",
                 "from pathlib import Path; import sys; import ascend_editable_smoke as m; "
                 "from importlib.metadata import version; assert m.VALUE == 1; "
                 "assert version(\"ascend-editable-smoke\") == \"1.2.3\"; "
                 "assert not Path(m.__file__).resolve().is_relative_to(Path(sys.argv[1]))",
                 str(project)],
                cwd=root,
                check=True,
            )
            if vcs_backend:
                subprocess.run([sys.executable, "-c", version_check], cwd=root, check=True)
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
