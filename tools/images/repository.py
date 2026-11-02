"""Luciole account, Dockerfile, and documentation policies."""

from __future__ import annotations

import fnmatch
import re
import shlex
from pathlib import Path

from image_kit.repository import ImageRepository as SharedRepository
from image_kit.repository import RepositoryError


class ImageRepository(SharedRepository):
    """Apply Luciole policies to the shared build engine."""

    def load(self) -> ImageRepository:
        """Load manifests and verify consumer account and COPY contracts.

        Returns
        -------
        ImageRepository
            Validated consumer repository.

        Raises
        ------
        RepositoryError
            If an account or Dockerfile contract is inconsistent.
        """
        super().load()
        for family in self.families.values():
            for variant in family.variants:
                for dependency in variant.dependencies:
                    parent = self.variants[dependency.key]
                    if variant.build_args.get("USERNAME") != parent.build_args.get(
                        "USERNAME"
                    ):
                        raise RepositoryError(
                            f"{family.name}: USERNAME must match the inherited account"
                        )
            self._validate_dockerfile(family.name, family.dockerfile)
        return self

    def _validate_dockerfile(self, name: str, dockerfile: Path) -> None:
        """Check argument wiring and require COPY sources in the impact inputs.

        Parameters
        ----------
        name:
            Image whose manifest supplies build arguments and input declarations.
        dockerfile:
            Dockerfile to inspect.

        Raises
        ------
        RepositoryError
            If arguments or copied files are absent from the declared contract.
        """
        declared = self.families[name].inputs
        content = dockerfile.read_text(encoding="utf-8")
        arguments = set(re.findall(r"(?im)^\s*ARG\s+([A-Z][A-Z0-9_]*)", content))
        if (
            missing := (
                set().union(
                    *(set(item.build_args) for item in self.families[name].variants)
                )
                | {"BASE_IMAGE"}
            )
            - arguments
        ):
            raise RepositoryError(
                f"{name}: build arguments not declared in Dockerfile: {missing}"
            )
        for line in content.splitlines():
            line = line.strip()
            if not line.upper().startswith("COPY ") or "--from=" in line:
                continue
            tokens = shlex.split(line)[1:]
            sources = [token for token in tokens if not token.startswith("--")][:-1]
            for source in sources:
                if not any(
                    fnmatch.fnmatchcase(source, pattern) for pattern in declared
                ):
                    raise RepositoryError(
                        f"{name}: COPY source missing from inputs: {source}"
                    )
                if not self.path(source).is_file():
                    raise RepositoryError(
                        f"{name}: COPY individual files, not directories: {source}"
                    )

    def validate_documentation(self) -> None:
        """Check bilingual READMEs, English-only docs and local Markdown links.

        Raises
        ------
        RepositoryError
            If a README pair, document language layout or local link is invalid.
        """
        if translations := sorted((self.root / "docs").glob("*_zh.md")):
            raise RepositoryError(f"docs must be English-only: {translations}")
        guides = [self.root / "README.md"] + [
            family.directory / "README.md" for family in self.families.values()
        ]
        for guide in guides:
            if guide.stem.endswith("_zh"):
                continue
            translated = guide.with_stem(guide.stem + "_zh")
            for source in (guide, translated):
                if (
                    not source.is_file()
                    or not source.read_text(encoding="utf-8").strip()
                ):
                    raise RepositoryError(f"missing bilingual guide: {source}")
                content = source.read_text(encoding="utf-8")
                counterpart = guide.name if source == translated else translated.name
                if not any(
                    f"]({prefix}{counterpart})" in content for prefix in ("", "./")
                ):
                    raise RepositoryError(f"{source}: missing link to {counterpart}")
                for target in re.findall(r"\]\(([^\s)]+)\)", content):
                    target = target.split("#", 1)[0]
                    if not target or "://" in target or target.startswith("mailto:"):
                        continue
                    if not (source.parent / target).exists():
                        raise RepositoryError(f"{source}: broken link {target}")
        for source in (self.root / "docs").glob("*.md"):
            content = source.read_text(encoding="utf-8")
            for target in re.findall(r"\]\(([^\s)]+)\)", content):
                target = target.split("#", 1)[0]
                if (
                    target
                    and "://" not in target
                    and not target.startswith("mailto:")
                    and not (source.parent / target).exists()
                ):
                    raise RepositoryError(f"{source}: broken link {target}")
