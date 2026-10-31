"""Load image contracts and derive deterministic build graphs."""

from __future__ import annotations

import fnmatch
import json
import re
import shlex
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any

import jsonschema
import yaml

RUNNERS = {"linux/amd64": "ubuntu-24.04", "linux/arm64": "ubuntu-24.04-arm"}
DIGEST = re.compile(r"sha256:[a-f0-9]{64}")


class RepositoryError(ValueError):
    """A configuration or execution error with an actionable message."""


class ManifestLoader(yaml.SafeLoader):
    """Reject duplicate keys instead of silently overriding build configuration."""

    def construct_mapping(self, node: yaml.MappingNode, deep: bool = False) -> dict[str, Any]:
        mapping: dict[str, Any] = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if not isinstance(key, str) or key in mapping:
                raise RepositoryError(f"manifest mapping key must be unique text: {key!r}")
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


def read_json(path: Path) -> dict[str, Any]:
    """Read a generated JSON document."""
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(value: Any, path: Path | None) -> None:
    """Write stable JSON to a file or standard output."""
    rendered = json.dumps(value, indent=2) + "\n"
    if path is None:
        print(rendered, end="")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")


def image_ref(owner: str, name: str, revision: str) -> str:
    """Return the existing seven-character SHA tag used for local tests."""
    if not re.fullmatch(r"[a-fA-F0-9]{40}", revision):
        raise RepositoryError("revision must be a full 40-character Git SHA")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]*", owner):
        raise RepositoryError("invalid registry owner")
    return f"ghcr.io/{owner.lower()}/{name}:sha-{revision[:7].lower()}"


class ImageRepository:
    """Own validated manifests, dependency selection, and Bake rendering."""

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.images: dict[str, dict[str, Any]] = {}

    def path(self, value: str) -> Path:
        """Resolve a portable repository-relative path without allowing escapes."""
        relative = PurePosixPath(value)
        if relative.is_absolute() or ".." in relative.parts or "\\" in value or ":" in value:
            raise RepositoryError(f"path must stay inside the repository: {value}")
        result = self.root / value
        if not result.resolve().is_relative_to(self.root):
            raise RepositoryError(f"path escapes repository: {value}")
        return result

    def load(self) -> ImageRepository:
        """Read all manifests and validate paths, build inputs, and graph edges."""
        schema = read_json(self.root / "schemas/image.schema.json")
        self.images.clear()
        for manifest in sorted(self.root.glob("src/*/image.yml")):
            self.path(manifest.relative_to(self.root).as_posix())
            raw = yaml.load(manifest.read_text(encoding="utf-8"), Loader=ManifestLoader)
            try:
                jsonschema.Draft202012Validator(schema).validate(raw)
            except jsonschema.ValidationError as error:
                raise RepositoryError(
                    f"{manifest.relative_to(self.root)}: {error.message}"
                ) from error
            name = raw["name"]
            if name != manifest.parent.name or name in self.images:
                raise RepositoryError(f"duplicate or mismatched image name: {name}")
            self.images[name] = raw
        if not self.images:
            raise RepositoryError("no src/<image>/image.yml manifests found")
        for name, image in self.images.items():
            dockerfile = self.path(image["dockerfile"])
            if not dockerfile.is_file():
                raise RepositoryError(f"{name}: missing Dockerfile")
            patterns = image["inputs"] + image["smoke"]["inputs"]
            for pattern in patterns:
                self.path(pattern)
                matches = list(self.root.glob(pattern))
                if not matches or any(not p.is_file() for p in matches):
                    raise RepositoryError(f"{name}: input must match files: {pattern}")
                for match in matches:
                    self.path(match.relative_to(self.root).as_posix())
            script = self.path(image["smoke"]["script"])
            if not script.is_file() or script.parent != self.root / "src/_tests":
                raise RepositoryError(f"{name}: smoke script must exist in src/_tests")
            if "src/_tests/_lib.sh" not in image["smoke"]["inputs"]:
                raise RepositoryError(f"{name}: smoke.inputs must include src/_tests/_lib.sh")
            base = image["base"]
            if "dependency" in base:
                parent = self.images.get(base["dependency"])
                if parent is None:
                    raise RepositoryError(f"{name}: unknown dependency {base['dependency']}")
                if not set(image["platforms"]).issubset(parent["platforms"]):
                    raise RepositoryError(f"{name}: dependency does not support its platforms")
                if image["build_args"].get("USERNAME") != parent["build_args"].get("USERNAME"):
                    raise RepositoryError(f"{name}: USERNAME must match the inherited account")
            elif not re.search(r":[^/:@]+$", base["image"]) or base["image"].endswith(
                (":latest", ":master")
            ):
                raise RepositoryError(f"{name}: external base requires an explicit version tag")
            self._validate_dockerfile(name, dockerfile)
        self.order(set(self.images))
        return self

    def _validate_dockerfile(self, name: str, dockerfile: Path) -> None:
        """Check argument wiring and require COPY sources in the impact inputs."""
        declared = self.images[name]["inputs"]
        content = dockerfile.read_text(encoding="utf-8")
        arguments = set(re.findall(r"(?im)^\s*ARG\s+([A-Z][A-Z0-9_]*)", content))
        if missing := (set(self.images[name]["build_args"]) | {"BASE_IMAGE"}) - arguments:
            raise RepositoryError(f"{name}: build arguments not declared in Dockerfile: {missing}")
        for line in content.splitlines():
            line = line.strip()
            if not line.upper().startswith("COPY ") or "--from=" in line:
                continue
            tokens = shlex.split(line)[1:]
            sources = [token for token in tokens if not token.startswith("--")][:-1]
            for source in sources:
                if not any(fnmatch.fnmatchcase(source, pattern) for pattern in declared):
                    raise RepositoryError(f"{name}: COPY source missing from inputs: {source}")
                if not self.path(source).is_file():
                    raise RepositoryError(
                        f"{name}: COPY individual files, not directories: {source}"
                    )

    def order(self, selected: set[str]) -> list[str]:
        """Topologically sort selected targets and reject dependency cycles."""
        ordered: list[str] = []
        visiting: set[str] = set()

        def visit(name: str) -> None:
            if name in visiting:
                raise RepositoryError(f"dependency cycle includes {name}")
            if name in ordered:
                return
            visiting.add(name)
            parent = self.images[name]["base"].get("dependency")
            if parent in selected:
                visit(parent)
            visiting.remove(name)
            ordered.append(name)

        for name in sorted(selected):
            visit(name)
        return ordered

    def affected(self, paths: list[str]) -> set[str]:
        """Select changed contracts and their transitive consumers."""
        infrastructure = ("tools/images/", "schemas/", ".github/workflows/")
        if any(
            path.startswith(infrastructure) or path in {"pyproject.toml", ".dockerignore"}
            for path in paths
        ):
            return set(self.images)
        selected: set[str] = set()
        for name, image in self.images.items():
            patterns = [
                f"src/{name}/image.yml",
                image["dockerfile"],
                *image["inputs"],
                image["smoke"]["script"],
                *image["smoke"]["inputs"],
            ]
            if any(fnmatch.fnmatchcase(path, pattern) for path in paths for pattern in patterns):
                selected.add(name)
        while True:
            expanded = selected | {
                name
                for name, image in self.images.items()
                if image["base"].get("dependency") in selected
            }
            if expanded == selected:
                return selected
            selected = expanded

    def changed_files(self, base: str, head: str) -> list[str]:
        """Read Git changes, including both sides of renames and deletions."""
        return subprocess.check_output(
            ["git", "diff", "--no-renames", "--name-only", base, head, "--"],
            cwd=self.root,
            text=True,
        ).splitlines()

    def plan(self, selected: set[str], changed: list[str] | None = None) -> dict[str, Any]:
        """Add build ancestors without expanding the publication set."""
        if unknown := selected - self.images.keys():
            raise RepositoryError(f"unknown images: {', '.join(sorted(unknown))}")
        platforms = {name: set(self.images[name]["platforms"]) for name in selected}
        queue = list(selected)
        while queue:
            name = queue.pop()
            parent = self.images[name]["base"].get("dependency")
            if parent:
                inherited = platforms.setdefault(parent, set())
                if platforms[name] - inherited:
                    inherited.update(platforms[name])
                    queue.append(parent)
        targets = [
            {
                "name": name,
                "platforms": [platform for platform in RUNNERS if platform in platforms[name]],
                "publish": name in selected,
                "reason": "selected" if name in selected else "dependency",
            }
            for name in self.order(set(platforms))
        ]
        matrix = [
            {"platform": platform, "platform_id": platform.split("/")[1], "runner": runner}
            for platform, runner in RUNNERS.items()
            if any(platform in target["platforms"] for target in targets)
        ]
        return {
            "schema_version": 1,
            "changed_files": changed or [],
            "targets": targets,
            "build_matrix": {"include": matrix},
        }

    def check_plan(self, plan: dict[str, Any]) -> None:
        """Reject stale or incomplete plans before running Docker commands."""
        selected = {target["name"] for target in plan["targets"] if target["publish"]}
        expected = self.plan(selected, plan["changed_files"])
        if plan != expected:
            raise RepositoryError("build plan does not match the current manifests")

    def bake(
        self,
        plan: dict[str, Any],
        owner: str,
        revision: str,
        platform: str,
        mode: str,
        source_repository: str,
        github_cache: bool = False,
    ) -> dict[str, Any]:
        """Render one native architecture, using same-commit target contexts."""
        self.check_plan(plan)
        targets: dict[str, Any] = {}
        for item in plan["targets"]:
            if platform not in item["platforms"]:
                continue
            name = item["name"]
            image = self.images[name]
            reference = image_ref(owner, name, revision)
            base = image["base"]
            parent = base.get("dependency")
            base_ref = "internal_base" if parent else base["image"]
            if not parent and base["digest"]:
                base_ref += "@" + base["digest"]
            args = {
                key: str(value).lower() if isinstance(value, bool) else str(value)
                for key, value in image["build_args"].items()
            }
            target: dict[str, Any] = {
                "context": image["context"],
                "dockerfile": image["dockerfile"],
                "platforms": [platform],
                "args": {**args, "BASE_IMAGE": base_ref},
                "contexts": {"internal_base": f"target:{parent}"} if parent else {},
                "labels": {
                    "org.opencontainers.image.source": f"https://github.com/{source_repository}",
                    "org.opencontainers.image.revision": revision,
                    "org.opencontainers.image.title": name,
                },
            }
            if github_cache:
                target["cache-from"] = [f"type=gha,scope={name}-{platform.split('/')[1]}"]
            if mode == "load":
                target.update(tags=[reference], output=["type=docker"])
            elif mode == "publish":
                target["output"] = (
                    [
                        f"type=image,name=ghcr.io/{owner.lower()}/{name},"
                        "push-by-digest=true,name-canonical=true,push=true"
                    ]
                    if item["publish"]
                    else ["type=cacheonly"]
                )
                if github_cache:
                    target["cache-to"] = [
                        f"type=gha,mode=max,scope={name}-{platform.split('/')[1]}"
                    ]
            else:
                raise RepositoryError(f"unsupported Bake mode: {mode}")
            targets[name] = target
        return {"group": {"default": {"targets": list(targets)}}, "target": targets}

    def validate_documentation(self) -> None:
        """Check bilingual guides and repository-relative Markdown links."""
        guides = (
            [self.root / "README.md"]
            + [self.root / "src" / name / "README.md" for name in self.images]
            + list((self.root / "docs").glob("*.md"))
        )
        for guide in guides:
            if guide.stem.endswith("_zh"):
                continue
            translated = guide.with_stem(guide.stem + "_zh")
            for source in (guide, translated):
                if not source.is_file() or not source.read_text(encoding="utf-8").strip():
                    raise RepositoryError(f"missing bilingual guide: {source}")
                content = source.read_text(encoding="utf-8")
                counterpart = guide.name if source == translated else translated.name
                if not any(f"]({prefix}{counterpart})" in content for prefix in ("", "./")):
                    raise RepositoryError(f"{source}: missing link to {counterpart}")
                for target in re.findall(r"\]\(([^\s)]+)\)", content):
                    target = target.split("#", 1)[0]
                    if not target or "://" in target or target.startswith("mailto:"):
                        continue
                    if not (source.parent / target).exists():
                        raise RepositoryError(f"{source}: broken link {target}")
