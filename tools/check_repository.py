"""Validate Luciole policies separately from the shared build engine."""

from pathlib import Path

from tools.images.repository import ImageRepository


def main() -> int:
    """Validate account, Dockerfile, and documentation contracts.

    Returns
    -------
    int
        Zero after all repository policies pass.

    Raises
    ------
    image_kit.repository.RepositoryError
        If a consumer contract is inconsistent.
    """
    repository = ImageRepository(Path.cwd()).load()
    repository.validate_documentation()
    print(f"Validated Luciole policies for {len(repository.families)} images")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
