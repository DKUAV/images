#!/bin/bash
# Run explicitly on the target server with NPU devices and compatible host drivers mounted.
set -euo pipefail

npu-smi info
python3 - <<'PYTHON'
import torch
import torch_npu

assert torch.npu.is_available()
assert torch.npu.device_count() > 0
left = torch.arange(16, dtype=torch.float32).reshape(4, 4)
right = torch.eye(4)
actual = left.npu() @ right.npu()
torch.npu.synchronize()
torch.testing.assert_close(actual.cpu(), left @ right)
print(f"NPU matrix multiplication passed on {torch.npu.device_count()} visible device(s)")
PYTHON
