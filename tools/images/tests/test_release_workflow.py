"""Execute the real release workflow's source-run and receipt validation."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest
import yaml


@pytest.mark.parametrize(
    "damage",
    [
        None,
        "run_id",
        "attempt",
        "workflow",
        "conclusion",
        "branch",
        "event",
        "revision",
        "owner",
        "registry",
        "repository",
    ],
)
def test_release_workflow_verifies_source(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, damage: str | None
) -> None:
    """Prevent unrelated, failed or mismatched runs from reaching version promotion.

    Parameters
    ----------
    tmp_path:
        Isolated workflow output directory.
    monkeypatch:
        Environment and GitHub CLI replacements.
    damage:
        Source-run or receipt corruption; None exercises acceptance.
    """
    root = Path(__file__).resolve().parents[3]
    workflow = yaml.safe_load(
        (root / ".github/workflows/release.yml").read_text(encoding="utf-8")
    )
    step = next(
        item
        for item in workflow["jobs"]["release"]["steps"]
        if item.get("name") == "Verify source run and download its receipt"
    )
    script = (
        step["run"]
        .split("<<'VERIFY_PUBLICATION'\n", 1)[1]
        .split("\nVERIFY_PUBLICATION", 1)[0]
    )
    monkeypatch.chdir(tmp_path)
    for name, value in {
        "SOURCE_RUN_ID": "123",
        "SOURCE_ATTEMPT": "2",
        "GITHUB_REPOSITORY": "DKUAV/images",
        "GITHUB_REPOSITORY_OWNER": "DKUAV",
        "GITHUB_ENV": str(tmp_path / "env"),
    }.items():
        monkeypatch.setenv(name, value)
    run: dict[str, Any] = {
        "conclusion": "success",
        "head_branch": "main",
        "event": "push",
        "path": ".github/workflows/publish-images.yml",
        "repository": {"full_name": "DKUAV/images"},
        "run_attempt": 2,
        "head_sha": "a" * 40,
    }
    identity = {
        "revision": "a" * 40,
        "repository": "DKUAV/images",
        "owner": "dkuav",
        "registry": "ghcr.io",
        "build_id": "123-2",
    }
    if damage == "run_id":
        monkeypatch.setenv("SOURCE_RUN_ID", "123/../other")
    elif damage == "attempt":
        run["run_attempt"] = 1
    elif damage == "workflow":
        run["path"] = ".github/workflows/release.yml"
    elif damage == "conclusion":
        run["conclusion"] = "failure"
    elif damage == "branch":
        run["head_branch"] = "feature"
    elif damage == "event":
        run["event"] = "pull_request"
    elif damage:
        identity[damage] = "different"
    calls: list[list[str]] = []

    def api(command: list[str], **kwargs: Any) -> str:
        """Return source-run metadata without calling GitHub.

        Parameters
        ----------
        command:
            GitHub CLI argument vector.
        **kwargs:
            Subprocess options.

        Returns
        -------
        str
            Source-run JSON.
        """
        calls.append(command)
        assert command == [
            "gh",
            "api",
            "repos/DKUAV/images/actions/runs/123/attempts/2",
        ]
        return json.dumps(run)

    def download(command: list[str], **kwargs: Any) -> subprocess.CompletedProcess[str]:
        """Provide the selected attempt's receipt without registry or network access.

        Parameters
        ----------
        command:
            GitHub CLI download command.
        **kwargs:
            Subprocess options.

        Returns
        -------
        subprocess.CompletedProcess[str]
            Successful artifact download.
        """
        calls.append(command)
        assert command == [
            "gh",
            "run",
            "download",
            "123",
            "--repo",
            "DKUAV/images",
            "--name",
            "publication-2",
            "--dir",
            "release-input",
        ]
        folder = tmp_path / "release-input"
        folder.mkdir()
        (folder / "publication.json").write_text(
            json.dumps({"identity": identity}), encoding="utf-8"
        )
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(subprocess, "check_output", api)
    monkeypatch.setattr(subprocess, "run", download)
    if damage:
        with pytest.raises(SystemExit):
            exec(compile(script, "release-workflow.py", "exec"), {})
        assert not (tmp_path / "env").exists()
        if damage == "run_id":
            assert not calls
    else:
        exec(compile(script, "release-workflow.py", "exec"), {})
        assert (tmp_path / "env").read_text() == f"RELEASE_REVISION={'a' * 40}\n"
