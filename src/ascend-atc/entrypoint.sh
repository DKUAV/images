#!/bin/bash
# Run the CANN 8.5.0 vendor initialization before starting shared SSH services.
# shellcheck disable=SC1091
source /usr/local/Ascend/ascend-toolkit/set_env.sh \
    && source "${ASCEND_HOME_PATH}/share/info/ascendnpu-ir/bin/set_env.sh" \
    && source /usr/local/Ascend/nnal/atb/set_env.sh \
    && exec /usr/local/bin/docker-entrypoint "$@"
