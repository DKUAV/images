#!/bin/bash
# Upgrade pip and delegate Luciole's combined requirements to image-kit's CUDA installer.
# Run as root beside cuda-pip-packages.sh; NVIDIA supplies the Python interpreter.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: luciole-cuda-pip-packages.sh --requirements <path>

Options:
  --requirements <path>  Combined common and Luciole requirements file (required)
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
if [ "$#" -ne 0 ] || [ -z "${REQUIREMENTS_FILE}" ] || [ ! -f "${REQUIREMENTS_FILE}" ] || [ ! -r "${REQUIREMENTS_FILE}" ]; then
    echo "luciole-cuda-pip-packages.sh: --requirements must name a readable file without positional arguments" >&2
    exit 64
fi

python3 -m pip install --upgrade pip
exec "$(dirname "$0")/cuda-pip-packages.sh" --requirements "${REQUIREMENTS_FILE}"
