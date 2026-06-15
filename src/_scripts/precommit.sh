#!/bin/bash
# Pre-cache pre-commit hook environments so they are available without network access.
# Must run as the target non-root user (USER directive before this RUN in the Dockerfile).
# Reads PRECOMMIT_CONFIG (default: /tmp/assets/.pre-commit-config.yaml).
set -euo pipefail

PRECOMMIT_CONFIG="${PRECOMMIT_CONFIG:-/tmp/assets/.pre-commit-config.yaml}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git init "$TMPDIR"
cp "$PRECOMMIT_CONFIG" "$TMPDIR/.pre-commit-config.yaml"
cd "$TMPDIR"
pre-commit install-hooks
