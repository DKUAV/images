#!/bin/bash
# Run development and vision checks in a specific Ascend Python environment.
assert_ascend_python_tools() {
    local python="$1"
    assert_cmd "Python development and vision tools ($python)" "$python" -E - <<'PY'
import build, editables, hatchling.build, hatch_vcs, packaging, pytest
import setuptools, setuptools_scm, uv_build, wheel
from importlib.metadata import version

import cv2
import h5py
import numpy as np
from skimage.color import rgb2gray

for tool in ("pre-commit", "ruff", "ty", "uv"):
    print(tool, version(tool))

assert hasattr(cv2, "ximgproc")
image = np.zeros((2, 2, 3), dtype=np.uint8)
gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
assert np.array_equal(gray, rgb2gray(image))
with h5py.File("smoke.h5", "w", driver="core", backing_store=False) as data:
    data["gray"] = gray
    assert np.array_equal(data["gray"][:], gray)
PY
}
