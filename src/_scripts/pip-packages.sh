#!/bin/bash
# Install common development packages and CUDA-specific Python tools.
# Run as root in the CUDA base; Ascend uses ascend-pip-packages.sh instead.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: pip-packages.sh --requirements <path>

Options:
  --requirements <path>  Common development requirements file (required)
  -h, --help             Show this help
EOF
}

REQUIREMENTS_FILE=""
if ! PARSED=$(getopt -o h -l help,requirements: -n "$(basename "$0")" -- "$@"); then
    usage >&2
    exit 64
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        --requirements)
            REQUIREMENTS_FILE="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
    esac
done
if [ "$#" -ne 0 ]; then
    echo "pip-packages.sh: unexpected positional arguments: $*" >&2
    usage >&2
    exit 64
fi
if [ -z "${REQUIREMENTS_FILE}" ] || [ ! -f "${REQUIREMENTS_FILE}" ] || [ ! -r "${REQUIREMENTS_FILE}" ]; then
    echo "pip-packages.sh: --requirements must name a readable file" >&2
    exit 64
fi

python3 -m pip install --upgrade pip
python3 -m pip install --no-cache-dir \
    --requirement "${REQUIREMENTS_FILE}" \
    "numpy<2.0.0" \
    opencv-contrib-python \
    scikit-image h5py onnxruntime onnx-simplifier \
    thop lap motmetrics filterpy ultralytics
