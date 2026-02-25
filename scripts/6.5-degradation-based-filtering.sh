#!/bin/bash

cd "$(dirname "$0")/.."

# 6.5 Degradation-Based Filtering (DBF)
# Systematically degrades connection quality (latency, jitter, packet loss).
# Aimed at plausible deniability by making censorship look like bad network.

source "$(dirname "$0")/common.sh"
CONTAINER_NAME=$(resolve_container BACKBONE)
INTERFACE=$(resolve_interface BACKBONE internal)
CONFIG_FILE="config/backbone/degradation.conf"

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
    qdisc=$(docker exec "$CONTAINER_NAME" tc qdisc show dev "$INTERFACE" | grep "netem")
    if [ -n "$qdisc" ]; then
        echo "Degradation-Based Filtering is ON"
        echo "  - Interface: $INTERFACE"
        echo "  - Config: $qdisc"
    else
        echo "Degradation-Based Filtering is OFF"
    fi
}

on() {
    local DELAY
    DELAY=$(get_config "delay" "200ms")
    local JITTER
    JITTER=$(get_config "jitter" "50ms")
    local LOSS
    LOSS=$(get_config "loss" "10%")
    local DISTRIBUTION
    DISTRIBUTION=$(get_config "distribution" "normal")

    echo "Enabling Degradation-Based Filtering (Simulating plausible deniability)..."
    echo "  - Adding Delay: $DELAY (Jitter: $JITTER, Distribution: $DISTRIBUTION)"
    echo "  - Adding Packet Loss: $LOSS"
    
    docker exec "$CONTAINER_NAME" tc qdisc del dev "$INTERFACE" root 2>/dev/null
    docker exec "$CONTAINER_NAME" tc qdisc add dev "$INTERFACE" root netem \
        delay "$DELAY" "$JITTER" distribution "$DISTRIBUTION" \
        loss "$LOSS"
    echo "Done."
}

off() {
    echo "Disabling Degradation-Based Filtering..."
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
