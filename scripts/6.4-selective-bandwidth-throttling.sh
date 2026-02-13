#!/bin/bash

cd "$(dirname "$0")/.."

# 6.4 Selective Bandwidth Throttling
# Reduces bandwidth for international traffic.
# Uses tc-tbf (Token Bucket Filter) for precise rate limiting.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
INTERFACE="eth1"
CONFIG_FILE="config/backbone/bandwidth_throttling.conf"

get_config() {
    local key=$1
    local default=$2
    if [ -f "$CONFIG_FILE" ]; then
        local val
        val=$(grep "^${key}=" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

status() {
    local qdisc
    qdisc=$(docker exec "$CONTAINER_NAME" tc qdisc show dev "$INTERFACE" | grep "tbf")
    if [ -n "$qdisc" ]; then
        echo "Selective Bandwidth Throttling is ON"
        echo "  - Interface: $INTERFACE"
        echo "  - Config: $qdisc"
    else
        echo "Selective Bandwidth Throttling is OFF"
    fi
}

on() {
    local RATE
    RATE=$(get_config "rate" "256kbit")
    local LATENCY
    LATENCY=$(get_config "latency" "50ms")
    local BURST
    BURST=$(get_config "burst" "1540")

    echo "Enabling Selective Bandwidth Throttling on $INTERFACE to $RATE..."
    docker exec "$CONTAINER_NAME" tc qdisc del dev "$INTERFACE" root 2>/dev/null
    docker exec "$CONTAINER_NAME" tc qdisc add dev "$INTERFACE" root tbf rate "$RATE" latency "$LATENCY" burst "$BURST"
    echo "Done."
}

off() {
    echo "Disabling Selective Bandwidth Throttling..."
    docker exec "$CONTAINER_NAME" tc qdisc del dev "$INTERFACE" root 2>/dev/null
    echo "Done."
}

case "$1" in
    on)
        on
        ;;
    off)
        off
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {on|off|status}"
        exit 1
        ;;
esac
