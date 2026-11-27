#!/bin/bash
# Run a command with the isolated 310B compilation environment.
set -eo pipefail

if (( $# == 0 )); then
    printf 'Usage: ascend-atc-310b COMMAND [ARG ...]\n' >&2
    exit 64
fi

# Retain non-CANN paths such as vendor Python and application modules.
toolkit=/opt/ascend-310b
for name in PATH LD_LIBRARY_PATH PYTHONPATH CMAKE_PREFIX_PATH; do
    IFS=: read -r -a entries <<< "${!name:-}"
    paths=()
    for entry in "${entries[@]}"; do
        case "$entry" in
            ''|/usr/local/Ascend|/usr/local/Ascend/*|"$toolkit"|"$toolkit"/*) ;;
            *) paths+=("$entry") ;;
        esac
    done
    if (( ${#paths[@]} )); then
        value=$(IFS=:; printf '%s' "${paths[*]}")
        export "$name=$value"
    else
        unset "$name"
    fi
done
unset ASCEND_TOOLKIT_HOME ASCEND_TOOLKIT_LATEST_HOME ASCEND_HOME_PATH \
    ASCEND_OPP_PATH ASCEND_AICPU_PATH ASCEND_CUSTOM_OPP_PATH TOOLCHAIN_HOME \
    "${!ATB_@}" "${!LCCL_@}" "${!BISHENG_@}"

# shellcheck disable=SC1091
source "$toolkit/cann/set_env.sh"
# shellcheck disable=SC1091
source "$toolkit/cann/share/info/ascendnpu-ir/bin/set_env.sh"
export LD_LIBRARY_PATH="$toolkit/cann/aarch64-linux/devlib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$@"
