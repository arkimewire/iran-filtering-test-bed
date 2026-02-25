#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 3.1 Individual and Range (CIDR) Blocking
# Blocks traffic to/from specific IP addresses or ranges.

CONTAINER_NAME=$(resolve_container BACKBONE)
BLOCKLIST_FILE="config/backbone/blocklist.conf"

get_blocked_ips() {
    if [ -f "$BLOCKLIST_FILE" ]; then
        # Exclude comments, empty lines, and convert newlines/spaces to comma-separated list
        grep -v '^#' "$BLOCKLIST_FILE" | grep -v '^[[:space:]]*$' | xargs | sed 's/ /, /g'
    else
        echo ""
    fi
}

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip ip_blocking >/dev/null 2>&1; then
        echo "IP Blocking is ON"
        docker exec "$CONTAINER_NAME" nft list table ip ip_blocking
    else
        echo "IP Blocking is OFF"
    fi
}

on() {
    local blocked_ips
    blocked_ips=$(get_blocked_ips)
    
    if [ -z "$blocked_ips" ]; then
        echo "No IPs found in $BLOCKLIST_FILE. Skipping."
        return
    fi

    echo "Enabling IP Blocking with IPs: $blocked_ips"
    docker exec "$CONTAINER_NAME" nft add table ip ip_blocking
    docker exec "$CONTAINER_NAME" nft add set ip ip_blocking ip_blocklist '{ type ipv4_addr; flags interval; }'
    docker exec "$CONTAINER_NAME" nft add element ip ip_blocking ip_blocklist "{ $blocked_ips }"
    
    docker exec "$CONTAINER_NAME" nft add chain ip ip_blocking forward '{ type filter hook forward priority filter; policy accept; }'
    nft_insert_priv_exemption "$CONTAINER_NAME" ip_blocking forward
    docker exec "$CONTAINER_NAME" nft add rule ip ip_blocking forward ip daddr @ip_blocklist drop
    docker exec "$CONTAINER_NAME" nft add rule ip ip_blocking forward ip saddr @ip_blocklist drop
    echo "Done."
}

off() {
    echo "Disabling IP Blocking..."
    docker exec "$CONTAINER_NAME" nft delete table ip ip_blocking 2>/dev/null
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
