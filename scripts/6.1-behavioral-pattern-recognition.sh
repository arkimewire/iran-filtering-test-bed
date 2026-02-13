#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 6.1 Behavioral Pattern Recognition and Statistics
# Simulates statistical filtering by dropping or rate-limiting traffic
# based on "suspicious" patterns (e.g., randomized drops for encrypted flows).

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
CONFIG_FILE="config/backbone/behavioral_pattern.conf"

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
    if docker exec "$CONTAINER_NAME" nft list table ip behavioral_pattern >/dev/null 2>&1; then
        echo "Behavioral Pattern Recognition is ON"
        docker exec "$CONTAINER_NAME" nft list table ip behavioral_pattern
    else
        echo "Behavioral Pattern Recognition is OFF"
    fi
}

on() {
    local drop_percent
    drop_percent=$(get_config "drop_percent" "5")
    local size_threshold
    size_threshold=$(get_config "size_threshold" "1000")
    local burst_rate
    burst_rate=$(get_config "burst_rate" "10")
    local burst_packets
    burst_packets=$(get_config "burst_packets" "20")

    echo "Enabling Behavioral Pattern Recognition (Simulating statistical analysis)..."
    
    docker exec "$CONTAINER_NAME" nft add table ip behavioral_pattern
    docker exec "$CONTAINER_NAME" nft add chain ip behavioral_pattern forward '{ type filter hook forward priority filter; policy accept; }'
    nft_insert_priv_exemption "$CONTAINER_NAME" behavioral_pattern forward
    
    echo "  - Injecting ${drop_percent}% packet loss for large encrypted flows (>${size_threshold} bytes)..."
    docker exec "$CONTAINER_NAME" nft add rule ip behavioral_pattern forward ip length \> "$size_threshold" numgen random mod 100 \< "$drop_percent" drop
    
    echo "  - Throttling connection bursts (>${burst_rate}/second)..."
    docker exec "$CONTAINER_NAME" nft add rule ip behavioral_pattern forward ct state new limit rate over "$burst_rate"/second burst "$burst_packets" packets drop

    echo "Done."
}

off() {
    echo "Disabling Behavioral Pattern Recognition..."
    docker exec "$CONTAINER_NAME" nft delete table ip behavioral_pattern 2>/dev/null
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
