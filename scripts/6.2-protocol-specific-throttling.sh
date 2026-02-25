#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 6.2 Protocol-Specific Throttling (UDP/QUIC)
# Blocks or throttles UDP traffic (e.g., port 443) to force TCP fallback.

CONTAINER_NAME=$(resolve_container BACKBONE)
CONFIG_FILE="config/backbone/protocol_throttling.conf"

get_udp_ports() {
    if [ -f "$CONFIG_FILE" ]; then
        local val
        val=$(grep "^udp_ports=" "$CONFIG_FILE" | head -1 | cut -d'=' -f2)
        echo "${val:-443}"
    else
        echo "443"
    fi
}

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip protocol_throttling >/dev/null 2>&1; then
        echo "Protocol-Specific Throttling is ON"
        docker exec "$CONTAINER_NAME" nft list table ip protocol_throttling
    else
        echo "Protocol-Specific Throttling is OFF"
    fi
}

on() {
    local UDP_THROTTLE_PORTS
    UDP_THROTTLE_PORTS=$(get_udp_ports)

    echo "Enabling Protocol-Specific Throttling (Blocking UDP on ports: $UDP_THROTTLE_PORTS)..."
    
    docker exec "$CONTAINER_NAME" nft add table ip protocol_throttling
    docker exec "$CONTAINER_NAME" nft add chain ip protocol_throttling forward '{ type filter hook forward priority filter; policy accept; }'
    nft_insert_priv_exemption "$CONTAINER_NAME" protocol_throttling forward
    
    echo "  - Forcing TCP fallback by blocking UDP on QUIC ports..."
    docker exec "$CONTAINER_NAME" nft add rule ip protocol_throttling forward udp dport "{ $UDP_THROTTLE_PORTS }" drop
    docker exec "$CONTAINER_NAME" nft add rule ip protocol_throttling forward udp sport "{ $UDP_THROTTLE_PORTS }" drop
    
    echo "Done."
}

off() {
    echo "Disabling Protocol-Specific Throttling..."
    docker exec "$CONTAINER_NAME" nft delete table ip protocol_throttling 2>/dev/null
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
