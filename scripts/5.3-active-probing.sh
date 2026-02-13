#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 5.3 Active Probing and Server Fingerprinting
# Simulates the result of active probing where servers identified as VPN/proxy 
# nodes are blacklisted.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
PROBED_IPS_FILE="config/backbone/probed_ips.conf"

get_probed_ips() {
    if [ -f "$PROBED_IPS_FILE" ]; then
        # Exclude comments and empty lines, extract IP/CIDR
        grep -v '^#' "$PROBED_IPS_FILE" | grep -v '^[[:space:]]*$' | awk '{print $1}' | xargs | sed 's/ /, /g'
    else
        echo ""
    fi
}

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip active_probing >/dev/null 2>&1; then
        echo "Active Probing (Blacklist Enforcement) is ON"
        docker exec "$CONTAINER_NAME" nft list table ip active_probing
    else
        echo "Active Probing (Blacklist Enforcement) is OFF"
    fi
}

on() {
    local ips
    ips=$(get_probed_ips)
    
    if [ -z "$ips" ]; then
        echo "No IPs found in $PROBED_IPS_FILE. Skipping."
        return
    fi

    echo "Enabling Active Probing Blacklist with IPs: $ips"
    docker exec "$CONTAINER_NAME" nft add table ip active_probing
    docker exec "$CONTAINER_NAME" nft add set ip active_probing probed_servers '{ type ipv4_addr; flags interval; }'
    docker exec "$CONTAINER_NAME" nft add element ip active_probing probed_servers "{ $ips }"
    
    docker exec "$CONTAINER_NAME" nft add chain ip active_probing forward '{ type filter hook forward priority filter; policy accept; }'
    nft_insert_priv_exemption "$CONTAINER_NAME" active_probing forward
    docker exec "$CONTAINER_NAME" nft add rule ip active_probing forward ip daddr @probed_servers drop
    docker exec "$CONTAINER_NAME" nft add rule ip active_probing forward ip saddr @probed_servers drop
    echo "Done."
}

off() {
    echo "Disabling Active Probing Blacklist..."
    docker exec "$CONTAINER_NAME" nft delete table ip active_probing 2>/dev/null
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
