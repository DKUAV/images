"""Luciole policies, smoke helpers and metadata-transfer regressions."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

import pytest
import yaml
from image_kit.publication import BuildIdentity, collect
from image_kit.repository import RepositoryError

from tools.images.repository import ImageRepository

ROOT = Path(__file__).resolve().parents[3]
REVISION = "a" * 40


def test_documentation_language_policy(tmp_path: Path) -> None:
    """Keep README translations required while allowing English-only docs.

    Parameters
    ----------
    tmp_path:
        Isolated repository documentation directory.
    """
    (tmp_path / "README.md").write_text("[Chinese](README_zh.md)\n", encoding="utf-8")
    (tmp_path / "README_zh.md").write_text("[English](README.md)\n", encoding="utf-8")
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "guide.md").write_text("# English guide\n", encoding="utf-8")
    repository = ImageRepository(tmp_path)
    repository.validate_documentation()
    (docs / "guide_zh.md").write_text("# Translation\n", encoding="utf-8")
    with pytest.raises(RepositoryError, match="English-only"):
        repository.validate_documentation()
    (docs / "guide_zh.md").unlink()
    (tmp_path / "README_zh.md").unlink()
    with pytest.raises(RepositoryError, match="missing bilingual guide|broken link"):
        repository.validate_documentation()


@pytest.mark.parametrize("hard_gate,expected", [("0", 0), ("1", 1)])
def test_shared_smoke_gate(hard_gate, expected):
    """Exercise real shell assertion handling independently of a Docker daemon."""
    bash = shutil.which("bash")
    git_bash = Path("C:/Program Files/Git/bin/bash.exe")
    if git_bash.exists():
        bash = str(git_bash)
    if bash is None:
        pytest.skip()
    library = (ROOT / "src/_tests/_lib.sh").read_text(encoding="utf-8")
    # Remove only the final environment assertion; the helpers execute unmodified.
    library = library.rsplit("assert_in_container", 1)[0]
    result = subprocess.run(
        [bash, "--noprofile", "--norc"],
        input=library + f"\nSMOKE_HARD_GATE={hard_gate}\nfail fixture\nsmoke_summary\n",
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
    )
    assert result.returncode == expected, result.stderr
    assert ("required" if expected else "advisory") in result.stderr


def test_real_repository_contracts() -> None:
    """Validate real image graph, account, COPY and README contracts."""
    repo = ImageRepository(ROOT).load()
    repo.validate_documentation()
    assert len(repo.families) == 4
    ascend = repo.families["luciole-ascend"]
    assert ascend.platforms == ("linux/arm64",)
    assert ascend.variants[0].base_digest is None
    assert not ascend.variants[0].dependencies
    assert ascend.variants[0].build_args["DEFAULT_USER"] == "root"
    assert ascend.variants[0].build_args["SSH_MODE"] == "key-only"
    assert not {"DEFAULT_UID", "DEFAULT_GID", "DEFAULT_GROUPS"} & set(
        ascend.variants[0].build_args
    )
    plan = repo.make_plan(repo.variants)
    workers = plan["build_matrix"]["include"]
    assert len(workers) == 3
    assert len({worker["worker_id"] for worker in workers}) == 3
    for worker in workers:
        names = {
            item["name"]
            for item in repo.worker_targets(
                plan, worker["platform"], worker["component"]
            )
        }
        assert names in (
            {"luciole-ascend"},
            {"luciole-cuda-base", "luciole-cuda-dev", "luciole-cuda-runtime"},
        )
    common = "vendor/image-kit/assets/python-dev-requirements.txt"
    assert repo.affected([common]) == set(repo.variants)
    assert {
        key[0]
        for key in repo.affected(
            ["vendor/image-kit/scripts/python/ascend-pip-packages.sh"]
        )
    } == {"luciole-ascend"}
    plan = repo.make_plan(repo.select(family="luciole-cuda-dev"))
    assert [(item["name"], item["publish"]) for item in plan["targets"]] == [
        ("luciole-cuda-base", False),
        ("luciole-cuda-dev", True),
    ]


@pytest.mark.parametrize(
    "change, message",
    [
        ("account", "USERNAME must match"),
        ("argument", "not declared"),
        ("copy", "missing from inputs"),
    ],
)
def test_repository_wiring(tmp_path: Path, change: str, message: str) -> None:
    """Keep account and Dockerfile wiring checks consumer-owned.

    Parameters
    ----------
    tmp_path:
        Temporary consumer.
    change:
        Invalid policy mutation.
    message:
        Expected diagnostic.
    """
    for family in (ROOT / "src").glob("*/image.yml"):
        raw = yaml.safe_load(family.read_text(encoding="utf-8"))
        raw["inputs"] = [raw["dockerfile"]]
        for item in raw["variants"]:
            item["tests"] = [{"script": "src/smoke.sh"}]
        path = tmp_path / family.relative_to(ROOT)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(raw), encoding="utf-8")
        dockerfile = tmp_path / raw["dockerfile"]
        args = set(raw["variants"][0]["build_args"]) | {"BASE_IMAGE"}
        dockerfile.write_text(
            "\n".join(f"ARG {name}" for name in sorted(args)), encoding="utf-8"
        )
    (tmp_path / "src/smoke.sh").write_text("true\n", encoding="utf-8")
    path = tmp_path / "src/luciole-cuda-dev/image.yml"
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if change == "account":
        raw["variants"][0]["build_args"]["USERNAME"] = "other"
    elif change == "argument":
        raw["variants"][0]["build_args"]["ROS_TAREGT"] = "ros-base"
    else:
        dockerfile = tmp_path / raw["dockerfile"]
        dockerfile.write_text(
            dockerfile.read_text() + "\nCOPY src/missing.sh /tmp/missing.sh\n",
            encoding="utf-8",
        )
    path.write_text(yaml.safe_dump(raw), encoding="utf-8")
    with pytest.raises(RepositoryError, match=message):
        ImageRepository(tmp_path).load()


@pytest.mark.parametrize("smoke_exit", [0, 2])
def test_large_workflow_metadata(tmp_path: Path, smoke_exit: int) -> None:
    """Transfer provenance safely and require exported smoke success before collection.

    Parameters
    ----------
    tmp_path:
        Output directory for workflow artifacts.
    smoke_exit:
        Simulated exit status from testing the immutable published images.
    """
    bash = shutil.which("bash")
    if bash is None or shutil.which("node") is None:
        pytest.skip()
    workflow = yaml.safe_load(
        (ROOT / ".github/workflows/build-native.yml").read_text(encoding="utf-8")
    )
    step = next(
        step
        for step in workflow["jobs"]["build"]["steps"]
        if step.get("name") == "Collect publication digests"
    )
    payload = {
        "demo--stack": {
            "containerimage.digest": "sha256:" + "b" * 64,
            "provenance": "x" * (256 * 1024)
            + "\nWRITE_BUILD_METADATA\n$(touch injected) `touch injected`",
        }
    }
    metadata = json.dumps(payload)
    script = (
        "python() {\n"
        '  printf "%s\\n" "$3" >> commands.log\n'
        f'  if [[ "$3" == test ]]; then return {smoke_exit}; fi\n'
        "  return 0\n}\n"
        + step["run"].replace(
            "${{ toJSON(steps.publish.outputs.metadata) }}", json.dumps(metadata)
        )
    )
    result = subprocess.run(
        [bash, "--noprofile", "--norc", "-e"],
        input=script,
        text=True,
        cwd=tmp_path,
        capture_output=True,
        check=False,
    )
    assert result.returncode == smoke_exit, result.stderr
    assert (tmp_path / "commands.log").read_text().splitlines() == (
        ["test", "collect"] if smoke_exit == 0 else ["test"]
    )
    assert (tmp_path / "build-metadata.json").read_text() == metadata
    assert not (tmp_path / "injected").exists()
    identity = BuildIdentity("ghcr.io", "example", "example/images", REVISION, "123-1")
    plan: dict[str, Any] = {
        "targets": [
            {
                "name": "demo",
                "variant": "stack",
                "target": "demo--stack",
                "platforms": ["linux/amd64"],
                "publish": True,
            }
        ]
    }
    assert (
        collect(
            plan,
            json.loads((tmp_path / "build-metadata.json").read_text()),
            identity,
            "linux/amd64",
        )["digests"][0]["digest"]
        == "sha256:" + "b" * 64
    )
