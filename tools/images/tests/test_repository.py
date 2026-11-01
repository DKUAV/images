"""Contract tests for impact planning, native builds, and release gates."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

from tools.images.cli import collect, merge, run, run_tests
from tools.images.repository import ImageRepository, RepositoryError, image_ref

ROOT = Path(__file__).resolve().parents[3]
REVISION = "a" * 40


@pytest.fixture
def repository(tmp_path: Path) -> ImageRepository:
    """Build an isolated three-image graph with real manifest validation."""
    (tmp_path / "schemas").mkdir()
    shutil.copy(ROOT / "schemas/image.schema.json", tmp_path / "schemas/image.schema.json")
    tests = tmp_path / "src/_tests"
    tests.mkdir(parents=True)
    (tests / "_lib.sh").write_text("# helpers\n", encoding="utf-8")
    scripts = tmp_path / "src/_scripts"
    scripts.mkdir()
    for name, parent in [("base", None), ("dev", "base"), ("runtime", "base")]:
        directory = tmp_path / "src" / name
        directory.mkdir()
        (directory / "Dockerfile").write_text(
            f"ARG BASE_IMAGE\nFROM ${{BASE_IMAGE}}\nARG USERNAME\n"
            f"COPY --chmod=0755 src/_scripts/{name}.sh /tmp/{name}.sh\n",
            encoding="utf-8",
        )
        (scripts / f"{name}.sh").write_text("#!/bin/bash\n", encoding="utf-8")
        (tests / f"smoke-{name}.sh").write_text("# smoke\n", encoding="utf-8")
        manifest = {
            "schema_version": 1,
            "name": name,
            "description": name,
            "dockerfile": f"src/{name}/Dockerfile",
            "context": ".",
            "platforms": ["linux/amd64", "linux/arm64"],
            "base": {"dependency": parent} if parent else {"image": "ubuntu:24.04", "digest": None},
            "build_args": {"USERNAME": "luciole"},
            "inputs": [f"src/_scripts/{name}.sh"],
            "smoke": {
                "script": f"src/_tests/smoke-{name}.sh",
                "inputs": ["src/_tests/_lib.sh"],
                "policy": "advisory" if name == "base" else "required",
            },
        }
        (directory / "image.yml").write_text(yaml.safe_dump(manifest), encoding="utf-8")
    return ImageRepository(tmp_path).load()


def edit(repository: ImageRepository, name: str, change) -> ImageRepository:
    """Change a fixture manifest, then run production validation."""
    path = repository.root / "src" / name / "image.yml"
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    change(raw)
    path.write_text(yaml.safe_dump(raw), encoding="utf-8")
    return repository.load()


@pytest.mark.parametrize(
    "paths,expected",
    [
        (["src/dev/Dockerfile"], {"dev"}),
        (["src/base/image.yml"], {"base", "dev", "runtime"}),
        (["src/_scripts/base.sh"], {"base", "dev", "runtime"}),
        (["src/_scripts/dev.sh"], {"dev"}),
        (["src/_scripts/unused.sh"], set()),
        (["src/_tests/smoke-runtime.sh"], {"runtime"}),
        (["src/_tests/_lib.sh"], {"base", "dev", "runtime"}),
        (["README.md", "src/dev/README_zh.md", "src/dev/docker-compose.yml"], set()),
        (["schemas/image.schema.json"], {"base", "dev", "runtime"}),
        ([".github/workflows/build-native.yml"], {"base", "dev", "runtime"}),
        (["tools/images/cli.py"], {"base", "dev", "runtime"}),
    ],
)
def test_change_impact(repository, paths, expected):
    """Track actual build/test inputs without rebuilding for usage docs."""
    assert repository.affected(paths) == expected


def test_build_closure_does_not_publish_ancestors(repository):
    """A dev-only release builds the current base without releasing its sibling."""
    plan = repository.plan({"dev"})
    assert [(item["name"], item["publish"]) for item in plan["targets"]] == [
        ("base", False),
        ("dev", True),
    ]
    assert {item["platform"] for item in plan["build_matrix"]["include"]} == {
        "linux/amd64",
        "linux/arm64",
    }
    repository.check_plan(plan)


def test_transitive_graph(repository):
    """Propagate changes through multiple internal base levels."""
    edit(repository, "runtime", lambda raw: raw.update(base={"dependency": "dev"}))
    assert repository.affected(["src/dev/Dockerfile"]) == {"dev", "runtime"}
    assert [target["name"] for target in repository.plan({"runtime"})["targets"]] == [
        "base",
        "dev",
        "runtime",
    ]


def test_empty_plan(repository):
    """A documentation-only change yields no native workers."""
    plan = repository.plan(set(), ["README.md"])
    assert plan["targets"] == []
    assert plan["build_matrix"] == {"include": []}


@pytest.mark.parametrize(
    "change,match",
    [
        (lambda raw: raw["base"].update(dependency="missing"), "unknown dependency"),
        (lambda raw: raw.update(platforms=["linux/riscv64"]), "not one of"),
        (lambda raw: raw.update(platforms=["linux/amd64", "linux/amd64"]), "non-unique"),
        (lambda raw: raw.update(inputs=["../escape.sh"]), "inside the repository"),
        (lambda raw: raw.update(inputs=["src/_scripts/missing.sh"]), "input must match"),
        (lambda raw: raw.update(inputs=["src/_scripts/runtime.sh"]), "missing from inputs"),
        (lambda raw: raw["smoke"].update(script="src/_tests/missing.sh"), "smoke script"),
        (lambda raw: raw["build_args"].update(USERNAME="other"), "USERNAME must match"),
        (lambda raw: raw.update(name="base"), "mismatched image name"),
    ],
)
def test_invalid_contracts(repository, change, match):
    """Reject broken contracts before starting an expensive build."""
    with pytest.raises(RepositoryError, match=match):
        edit(repository, "dev", change)


def test_duplicate_yaml_key(repository):
    """Reject configuration overrides hidden by ordinary YAML loading."""
    manifest = repository.root / "src/dev/image.yml"
    with manifest.open("a", encoding="utf-8") as stream:
        stream.write("name: dev\n")
    with pytest.raises(RepositoryError, match="unique text"):
        repository.load()


def test_unknown_build_argument(repository):
    """A typo must not silently become an unused Docker build argument."""
    with pytest.raises(RepositoryError, match="not declared in Dockerfile"):
        edit(repository, "dev", lambda raw: raw["build_args"].update(ROS_TAREGT="ros-base"))


def test_cycles(repository):
    """Reject a cycle even when every individual dependency exists."""
    with pytest.raises(RepositoryError, match="cycle"):
        edit(repository, "base", lambda raw: raw.update(base={"dependency": "dev"}))


def test_parent_can_support_more_platforms(repository):
    """Allow an amd64-only child of a dual-platform base."""
    edit(repository, "dev", lambda raw: raw.update(platforms=["linux/amd64"]))
    plan = repository.plan({"dev"})
    arm = repository.bake(plan, "DKUAV", REVISION, "linux/arm64", "load", "dkuav/images")
    assert arm["target"] == {}
    assert [worker["platform"] for worker in plan["build_matrix"]["include"]] == ["linux/amd64"]


def test_parent_must_cover_child_platforms(repository):
    """Fail rather than silently building a child against the wrong architecture."""
    with pytest.raises(RepositoryError, match="support its platforms"):
        edit(repository, "base", lambda raw: raw.update(platforms=["linux/amd64"]))


@pytest.mark.parametrize("platform", ["linux/amd64", "linux/arm64"])
def test_bake_modes(repository, platform):
    """Connect same-commit bases and keep PR caches read-only."""
    plan = repository.plan({"dev"})
    load = repository.bake(plan, "DKUAV", REVISION, platform, "load", "dkuav/images")
    child = load["target"]["dev"]
    assert child["contexts"] == {"internal_base": "target:base"}
    assert child["args"]["BASE_IMAGE"] == "internal_base"
    assert child["platforms"] == [platform]
    assert child["tags"] == ["ghcr.io/dkuav/dev:sha-aaaaaaa"]
    assert all("cache-to" not in value for value in load["target"].values())
    publish = repository.bake(plan, "dkuav", REVISION, platform, "publish", "dkuav/images")
    assert publish["target"]["base"]["output"] == ["type=cacheonly"]
    assert "push-by-digest=true" in publish["target"]["dev"]["output"][0]
    assert "tags" not in publish["target"]["dev"]


def test_cache_opt_in(repository):
    """Keep local builds credential-free and GitHub caches architecture-scoped."""
    plan = repository.plan({"dev"})
    local = repository.bake(plan, "dkuav", REVISION, "linux/amd64", "load", "dkuav/images")
    assert all("cache-from" not in target for target in local["target"].values())
    for mode in ("load", "publish"):
        bake = repository.bake(
            plan, "dkuav", REVISION, "linux/arm64", mode, "dkuav/images", github_cache=True
        )
        for name, target in bake["target"].items():
            assert target["cache-from"] == [f"type=gha,scope={name}-arm64"]
            assert ("cache-to" in target) == (mode == "publish")


def test_pinned_base(repository):
    """Append a supplied external digest while preserving its version tag."""
    edit(repository, "base", lambda raw: raw["base"].update(digest="sha256:" + "b" * 64))
    bake = repository.bake(
        repository.plan({"base"}), "dkuav", REVISION, "linux/amd64", "load", "dkuav/images"
    )
    assert bake["target"]["base"]["args"]["BASE_IMAGE"] == "ubuntu:24.04@sha256:" + "b" * 64


@pytest.mark.parametrize(
    "base",
    [
        {"image": "ubuntu:latest", "digest": None},
        {"image": "ubuntu", "digest": None},
        {"image": "ubuntu:24.04"},
    ],
)
def test_external_base_contract(repository, base):
    """Require an explicit version and an explicit digest policy."""
    with pytest.raises(RepositoryError):
        edit(repository, "base", lambda raw: raw.update(base=base))


def test_stale_plan(repository):
    """Prevent an incomplete or edited plan from bypassing release selection."""
    plan = repository.plan({"dev"})
    plan["targets"].pop(0)
    with pytest.raises(RepositoryError, match="plan does not match"):
        repository.check_plan(plan)


def test_git_deletion_and_rename_paths(repository, monkeypatch):
    """Disable rename collapsing so old input names still invalidate consumers."""

    def check(command, **kwargs):
        assert "--no-renames" in command
        return "src/_scripts/dev.sh\nsrc/_scripts/renamed.sh\n"

    monkeypatch.setattr(subprocess, "check_output", check)
    assert repository.affected(repository.changed_files("base", "head")) == {"dev"}


def test_cli_plan_output(repository):
    """Expose the same stable plan and runner matrix to local users and CI."""
    output = repository.root / "plan.json"
    github = repository.root / "github-output"
    assert (
        run(
            [
                "--root",
                str(repository.root),
                "plan",
                "--image",
                "dev",
                "--output",
                str(output),
                "--github-output",
                str(github),
            ]
        )
        == 0
    )
    assert json.loads(output.read_text())["targets"][0]["publish"] is False
    assert "has_build=true" in github.read_text()


def test_smoke_policy_and_docker_failure(repository, monkeypatch):
    """Pass assertion policy into the container but never suppress Docker errors."""
    calls = []

    def docker(command, **kwargs):
        calls.append(command)
        return subprocess.CompletedProcess(command, 125 if "SMOKE_HARD_GATE=0" in command else 0)

    monkeypatch.setattr(subprocess, "run", docker)
    args = argparse.Namespace(platform="linux/amd64", owner="dkuav", revision=REVISION)
    with pytest.raises(RepositoryError, match="base"):
        run_tests(repository, args, repository.plan({"dev"}))
    assert len(calls) == 2
    assert "--pull=never" in calls[0]
    assert "SMOKE_HARD_GATE=1" in calls[1]
    assert "readonly" in calls[0][calls[0].index("--mount") + 1]


def release_args(repository):
    """Create digest artifacts for a dev-only, two-platform release."""
    directory = repository.root / "digests"
    directory.mkdir()
    for arch in ("amd64", "arm64"):
        (directory / f"{arch}.json").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "digests": [
                        {
                            "name": "dev",
                            "platform": f"linux/{arch}",
                            "digest": "sha256:" + "b" * 64,
                            "owner": "dkuav",
                            "revision": REVISION,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
    return argparse.Namespace(
        digests=directory, owner="dkuav", revision=REVISION, ref="refs/heads/main", dry_run=False
    )


@pytest.mark.parametrize(
    "ref,tags",
    [
        ("refs/heads/main", ["main", "latest"]),
        ("refs/tags/v1.2", ["v1.2"]),
        ("refs/heads/feature", []),
    ],
)
def test_merge_tags(repository, monkeypatch, ref, tags):
    """Merge architecture digests before advancing compatible public tags."""
    args = release_args(repository)
    args.ref = ref
    calls = []
    monkeypatch.setattr(subprocess, "run", lambda command, **kwargs: calls.append(command))
    merge(args, repository.plan({"dev"}))
    assert len(calls) == (2 if tags else 1)
    assert calls[0][5] == "ghcr.io/dkuav/dev:sha-aaaaaaa"
    assert len([value for value in calls[0] if "@sha256:" in value]) == 2
    for tag in tags:
        assert f"ghcr.io/dkuav/dev:{tag}" in calls[1]


def test_merge_dry_run(repository, monkeypatch, capsys):
    """Allow command review without registry mutations."""
    args = release_args(repository)
    args.dry_run = True
    calls = []
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: calls.append(a))
    merge(args, repository.plan({"dev"}))
    assert calls == []
    assert "ghcr.io/dkuav/dev:latest" in capsys.readouterr().out


def test_manifest_failure_stops_tag_promotion(repository, monkeypatch):
    """A registry failure creating SHA manifests must prevent floating updates."""
    args = release_args(repository)
    calls = []

    def fail(command, **kwargs):
        calls.append(command)
        raise subprocess.CalledProcessError(1, command)

    monkeypatch.setattr(subprocess, "run", fail)
    with pytest.raises(subprocess.CalledProcessError):
        merge(args, repository.plan({"dev"}))
    assert len(calls) == 1
    assert all(":latest" not in argument for argument in calls[0])


@pytest.mark.parametrize("damage", ["missing", "duplicate", "revision", "digest"])
def test_incomplete_release_never_updates_tags(repository, monkeypatch, damage):
    """Validate the entire artifact set before the first registry mutation."""
    args = release_args(repository)
    arm = args.digests / "arm64.json"
    data = json.loads(arm.read_text())
    if damage == "missing":
        arm.unlink()
    else:
        if damage == "duplicate":
            data["digests"][0]["platform"] = "linux/amd64"
        elif damage == "revision":
            data["digests"][0]["revision"] = "c" * 40
        else:
            data["digests"][0]["digest"] = "broken"
        arm.write_text(json.dumps(data), encoding="utf-8")
    calls = []
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: calls.append(a))
    with pytest.raises(RepositoryError):
        merge(args, repository.plan({"dev"}))
    assert calls == []


def test_collect_only_published_images(repository):
    """Dependency-only metadata must not become a published digest artifact."""
    metadata = repository.root / "metadata.json"
    metadata.write_text(json.dumps({"dev": {"containerimage.digest": "sha256:" + "b" * 64}}))
    args = argparse.Namespace(
        metadata=metadata,
        output=repository.root / "digests.json",
        platform="linux/amd64",
        owner="dkuav",
        revision=REVISION,
    )
    collect(args, repository.plan({"dev"}))
    assert [item["name"] for item in json.loads(args.output.read_text())["digests"]] == ["dev"]


def test_collect_large_workflow_metadata(repository):
    """Transfer large provenance and shell metacharacters without exec-size limits."""
    bash = shutil.which("bash")
    if bash is None or shutil.which("node") is None:
        pytest.skip("Bash and Node are required for the workflow metadata transfer")
    workflow = yaml.safe_load((ROOT / ".github/workflows/build-native.yml").read_text())
    step = next(
        step
        for step in workflow["jobs"]["build"]["steps"]
        if step.get("name") == "Collect publication digests"
    )
    # Linux limits each argument/environment string to about 128 KiB. Exercise
    # the real workflow with larger data and attempted shell/JS interpolation.
    metadata = json.dumps(
        {
            "dev": {
                "containerimage.digest": "sha256:" + "b" * 64,
                "buildx.build.provenance": {
                    "payload": "x" * (256 * 1024)
                    + "\nWRITE_BUILD_METADATA\n$(touch injected) `touch injected` "
                    + '");require("node:fs").writeFileSync("injected", "x");//'
                },
            }
        },
        indent=2,
    )
    script = step["run"].split("python -m tools.images collect", 1)[0]
    script = script.replace("${{ toJSON(steps.publish.outputs.metadata) }}", json.dumps(metadata))
    subprocess.run(
        [bash, "--noprofile", "--norc", "-e"],
        input=script,
        text=True,
        cwd=repository.root,
        capture_output=True,
        check=True,
    )
    metadata_path = repository.root / "build-metadata.json"
    assert metadata_path.read_text() == metadata
    assert not (repository.root / "injected").exists()
    args = argparse.Namespace(
        metadata=metadata_path,
        output=repository.root / "digests.json",
        platform="linux/arm64",
        owner="dkuav",
        revision=REVISION,
    )
    collect(args, repository.plan({"dev"}))
    assert json.loads(args.output.read_text())["digests"][0]["digest"] == "sha256:" + "b" * 64


def test_missing_publish_metadata(repository):
    """A missing exporter digest prevents the native worker from succeeding."""
    metadata = repository.root / "metadata.json"
    metadata.write_text("{}")
    args = argparse.Namespace(
        metadata=metadata,
        output=repository.root / "digests.json",
        platform="linux/amd64",
        owner="dkuav",
        revision=REVISION,
    )
    with pytest.raises(RepositoryError, match="digest metadata"):
        collect(args, repository.plan({"dev"}))


def test_unknown_image_and_revision(repository):
    """Reject typos rather than silently producing an empty release."""
    with pytest.raises(RepositoryError, match="unknown images"):
        repository.plan({"typo"})
    with pytest.raises(RepositoryError, match="full 40-character"):
        image_ref("dkuav", "dev", "short")


def test_real_repository_contracts():
    """Keep production manifests, COPY sources, and bilingual links synchronized."""
    repository = ImageRepository(ROOT).load()
    repository.validate_documentation()
    assert len(repository.images) == 4
    ascend = repository.images["luciole-ascend"]
    assert ascend["platforms"] == ["linux/arm64"]
    assert "dependency" not in ascend["base"]
    assert ascend["base"]["digest"] is None
    common_python = "src/_assets/python-dev-requirements.txt"
    assert common_python in ascend["inputs"]
    assert common_python in repository.images["luciole-cuda-base"]["inputs"]
    assert repository.affected([common_python]) == set(repository.images)
    assert repository.affected(["src/_scripts/ascend-pip-packages.sh"]) == {"luciole-ascend"}
    assert repository.affected(["src/_scripts/user.sh"]) == set(repository.images)
    plan = repository.plan({"luciole-ascend"})
    assert [item["platform"] for item in plan["build_matrix"]["include"]] == ["linux/arm64"]
    assert [item["name"] for item in plan["targets"]] == ["luciole-ascend"]
    bake = repository.bake(plan, "dkuav", REVISION, "linux/arm64", "load", "dkuav/images", False)
    assert bake["target"]["luciole-ascend"]["args"]["BASE_IMAGE"] == ascend["base"]["image"]


@pytest.mark.parametrize("hard_gate,expected", [("0", 0), ("1", 1)])
def test_shared_smoke_gate(hard_gate, expected):
    """Exercise real shell assertion handling independently of a Docker daemon."""
    bash = shutil.which("bash")
    git_bash = Path("C:/Program Files/Git/bin/bash.exe")
    if git_bash.exists():
        bash = str(git_bash)
    if bash is None:
        pytest.skip("Bash is unavailable")
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
