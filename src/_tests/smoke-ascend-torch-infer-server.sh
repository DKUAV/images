#!/bin/bash
# Check the inference server dependencies without NPU devices or a MinIO server.
# Sourced after _lib.sh by tools.images test.
set -uo pipefail

# shellcheck disable=SC1091
source /etc/profile.d/ascend-dev.sh

header "Inference server packages and inherited PEFT versions"
assert_cmd "Python package check" ascend-pip-check
assert_cmd "Inherited PEFT package versions are preserved" python3 -c '
from importlib.metadata import version
from pathlib import Path

for line in Path("/opt/image-python/infer-server-constraints.txt").read_text(encoding="utf-8").splitlines():
    package, expected = line.split("==", 1)
    actual = version(package)
    assert actual == expected, f"{package}: expected {expected}, got {actual}"
for package in ("flask", "minio"):
    print(f"{package}=={version(package)}")
'
assert_cmd "Flask CLI" python3 -m flask --version
assert_cmd "Flask handles a JSON request" python3 -c '
from flask import Flask

app = Flask("infer-server-smoke")
app.add_url_rule("/health", view_func=lambda: {"status": "ok"})
with app.test_client() as client:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json == {"status": "ok"}
'
assert_cmd "MinIO client initializes without network access" python3 -c '
from minio import Minio

client = Minio("localhost:9000", secure=False)
assert callable(client.get_object) and callable(client.put_object)
'

smoke_summary
