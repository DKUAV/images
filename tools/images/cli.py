"""Command-line interfaces shared by local builds and GitHub Actions."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

import yaml

from .repository import (
    DIGEST,
    RUNNERS,
    ImageRepository,
    RepositoryError,
    image_ref,
    read_json,
    write_json,
)


def parser() -> argparse.ArgumentParser:
    """Describe the supported repository operations."""
    result = argparse.ArgumentParser(prog="images")
    result.add_argument("--root", type=Path, default=Path.cwd())
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("validate", help="validate manifests, inputs and bilingual guide links")
    commands.add_parser("list", help="list images and their bases")
    plan = commands.add_parser("plan", help="select affected images and their build ancestors")
    selection = plan.add_mutually_exclusive_group()
    selection.add_argument("--all", action="store_true")
    selection.add_argument("--image")
    plan.add_argument("--base")
    plan.add_argument("--head")
    plan.add_argument("--output", type=Path)
    plan.add_argument("--github-output", type=Path)
    for name in ("bake", "test", "collect", "merge"):
        command = commands.add_parser(name)
        command.add_argument("--plan", type=Path, required=True)
        command.add_argument("--owner", required=True)
        command.add_argument("--revision", required=True)
        if name != "merge":
            command.add_argument("--platform", choices=list(RUNNERS), required=True)
        if name == "bake":
            command.add_argument("--mode", choices=["load", "publish"], required=True)
            command.add_argument("--repository", default="dkuav/images")
            command.add_argument("--github-cache", action="store_true")
            command.add_argument("--output", type=Path)
        elif name == "collect":
            command.add_argument("--metadata", type=Path, required=True)
            command.add_argument("--output", type=Path, required=True)
        elif name == "merge":
            command.add_argument("--digests", type=Path, required=True)
            command.add_argument("--ref", required=True)
            command.add_argument("--dry-run", action="store_true")
    return result


def run_tests(repo: ImageRepository, args: argparse.Namespace, plan: dict) -> None:
    """Run every selected contract, including dependency-only images."""
    failed: list[str] = []
    for target in plan["targets"]:
        if args.platform not in target["platforms"]:
            continue
        name = target["name"]
        smoke = repo.images[name]["smoke"]
        script = repo.path(smoke["script"]).name
        hard_gate = "1" if smoke["policy"] == "required" else "0"
        print(f"Testing {name} on {args.platform} ({smoke['policy']})", flush=True)
        result = subprocess.run(
            [
                "docker",
                "run",
                "--rm",
                "--pull=never",
                "--env",
                f"SMOKE_HARD_GATE={hard_gate}",
                "--mount",
                f"type=bind,source={repo.root / 'src/_tests'},target=/tmp/smoke,readonly",
                image_ref(args.owner, name, args.revision),
                "bash",
                "-lc",
                f"source /tmp/smoke/_lib.sh && source {shlex.quote('/tmp/smoke/' + script)}",
            ],
            check=False,
        )
        # Advisory assertion handling belongs to _lib.sh. Docker/startup errors remain fatal.
        if result.returncode:
            failed.append(name)
    if failed:
        raise RepositoryError(f"smoke execution failed: {', '.join(failed)}")


def collect(args: argparse.Namespace, plan: dict) -> None:
    """Export only publishable digests from the native Bake metadata."""
    metadata = read_json(args.metadata)
    records = []
    for target in plan["targets"]:
        if not target["publish"] or args.platform not in target["platforms"]:
            continue
        name = target["name"]
        image_ref(args.owner, name, args.revision)
        digest = metadata.get(name, {}).get("containerimage.digest", "")
        if not DIGEST.fullmatch(digest):
            raise RepositoryError(f"missing or invalid digest metadata for {name}")
        records.append(
            {
                "name": name,
                "platform": args.platform,
                "digest": digest,
                "revision": args.revision,
                "owner": args.owner.lower(),
            }
        )
    write_json({"schema_version": 1, "digests": records}, args.output)


def merge(args: argparse.Namespace, plan: dict) -> None:
    """Validate all architectures before creating SHA and floating manifests."""
    expected = {
        (target["name"], platform)
        for target in plan["targets"]
        if target["publish"]
        for platform in target["platforms"]
    }
    found: dict[tuple[str, str], str] = {}
    for path in sorted(args.digests.glob("*.json")):
        data = read_json(path)
        if data.get("schema_version") != 1:
            raise RepositoryError(f"unsupported digest artifact: {path}")
        for record in data["digests"]:
            key = (record["name"], record["platform"])
            if key in found or key not in expected:
                raise RepositoryError(f"duplicate or unexpected digest: {key}")
            if record["revision"] != args.revision or record["owner"] != args.owner.lower():
                raise RepositoryError(f"digest artifact is from a different build: {key}")
            if not DIGEST.fullmatch(record["digest"]):
                raise RepositoryError(f"invalid digest for {key}")
            found[key] = record["digest"]
    if found.keys() != expected:
        raise RepositoryError(f"missing architecture digests: {sorted(expected - found.keys())}")
    ref = args.ref
    if ref.startswith("refs/tags/") and not re.fullmatch(r"v[A-Za-z0-9_.-]{0,127}", ref[10:]):
        raise RepositoryError("release tag must start with v and be a valid Docker tag")
    commands: list[list[str]] = []
    published = [target for target in plan["targets"] if target["publish"]]
    for target in published:
        name = target["name"]
        reference = image_ref(args.owner, name, args.revision)
        repository = reference.rsplit(":", 1)[0]
        commands.append(
            [
                "docker",
                "buildx",
                "imagetools",
                "create",
                "--tag",
                reference,
                *[f"{repository}@{found[name, platform]}" for platform in target["platforms"]],
            ]
        )
    # Create all SHA manifests first. Only then advance convenience/release tags.
    for target in published:
        reference = image_ref(args.owner, target["name"], args.revision)
        repository = reference.rsplit(":", 1)[0]
        tags = ["main", "latest"] if ref == "refs/heads/main" else []
        if ref.startswith("refs/tags/"):
            tags.append(ref[10:])
        if tags:
            commands.append(
                [
                    "docker",
                    "buildx",
                    "imagetools",
                    "create",
                    *[part for tag in tags for part in ("--tag", f"{repository}:{tag}")],
                    reference,
                ]
            )
    for command in commands:
        print(json.dumps(command), flush=True)
        if not args.dry_run:
            subprocess.run(command, check=True)


def run(arguments: list[str] | None = None) -> int:
    """Execute one command; keep planning and rendering free of Docker side effects."""
    args = parser().parse_args(arguments)
    repo = ImageRepository(args.root).load()
    if args.command == "validate":
        repo.validate_documentation()
        print(f"Validated {len(repo.images)} image manifests and bilingual documentation")
    elif args.command == "list":
        for name, image in repo.images.items():
            print(f"{name}: {image['base']} ({', '.join(image['platforms'])})")
    elif args.command == "plan":
        changed: list[str] = []
        if args.all:
            selected = set(repo.images)
        elif args.image:
            selected = {args.image}
        elif args.base and args.head:
            changed = repo.changed_files(args.base, args.head)
            selected = repo.affected(changed)
        else:
            raise RepositoryError("plan requires --all, --image, or both --base and --head")
        plan = repo.plan(selected, changed)
        write_json(plan, args.output)
        if args.github_output:
            with args.github_output.open("a", encoding="utf-8") as output:
                output.write(f"has_build={'true' if plan['targets'] else 'false'}\n")
                output.write(f"build_matrix={json.dumps(plan['build_matrix'])}\n")
    else:
        plan = read_json(args.plan)
        repo.check_plan(plan)
        if args.command == "bake":
            write_json(
                repo.bake(
                    plan,
                    args.owner,
                    args.revision,
                    args.platform,
                    args.mode,
                    args.repository,
                    args.github_cache,
                ),
                args.output,
            )
        elif args.command == "test":
            run_tests(repo, args, plan)
        elif args.command == "collect":
            collect(args, plan)
        elif args.command == "merge":
            merge(args, plan)
    return 0


def main() -> int:
    """Report expected operational errors without Python tracebacks."""
    try:
        return run()
    except (
        RepositoryError,
        OSError,
        ValueError,
        KeyError,
        yaml.YAMLError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"images: error: {error}", file=sys.stderr)
        return 2
