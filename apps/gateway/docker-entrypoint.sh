#!/bin/sh
set -eu

# Explicit CLI arguments replace the environment-driven defaults.
if [ "$#" -gt 0 ]; then
    exec /usr/local/bin/nightcord-gateway "$@"
fi

set -- /usr/local/bin/nightcord-gateway \
    --bind 0.0.0.0:8787 \
    --data-dir /data \
    --profile "${NIGHTCORD_GATEWAY_PROFILE:-web}"

# Split only on commas, without glob expansion or interpreting shell syntax.
if [ -n "${NIGHTCORD_GATEWAY_ORIGINS:-}" ]; then
    set -f
    IFS=,
    for origin in $NIGHTCORD_GATEWAY_ORIGINS; do
        if [ -z "$origin" ]; then
            echo 'NIGHTCORD_GATEWAY_ORIGINS contains an empty origin.' >&2
            exit 1
        fi
        set -- "$@" --allow-origin "$origin"
    done
    unset IFS
fi

# Tokens are read directly by the process from its environment, never argv.
exec "$@"
