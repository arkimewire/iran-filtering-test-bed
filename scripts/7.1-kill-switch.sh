#!/bin/bash

# 7.1 Total National Internet Shutdown (The "Kill Switch")
# Simulates the total internet blackout by disconnecting IXP and ISPs.
# This cuts all traffic between the national peering point and local providers.

CONTAINER_NAME="clab-iran-filtering-iran-ixp"
INTERFACE="eth1" # Interface towards iran-isp

status() {
    if docker exec "$CONTAINER_NAME" nft list table inet kill_switch >/dev/null 2>&1; then
        echo "Kill Switch is ON (Internet is SHUT DOWN)"
        docker exec "$CONTAINER_NAME" nft list table inet kill_switch
    else
        echo "Kill Switch is OFF (Internet is ACTIVE)"
    fi
}

on() {
    echo "Activating Kill Switch (Severing IXP-ISP link)..."
    
    # Use inet family for transparency
    docker exec "$CONTAINER_NAME" nft add table inet kill_switch
    # High priority to catch all packets before other rules
    docker exec "$CONTAINER_NAME" nft add chain inet kill_switch forward '{ type filter hook forward priority -100; policy accept; }'
    
    # Block bidirectional traffic on the ISP-facing interface
    echo "  - Interface: $INTERFACE (Dropping all traffic)"
    docker exec "$CONTAINER_NAME" nft add rule inet kill_switch forward iifname "$INTERFACE" drop
    docker exec "$CONTAINER_NAME" nft add rule inet kill_switch forward oifname "$INTERFACE" drop
    
    echo "Done."
}

off() {
    echo "Deactivating Kill Switch (Restoring connectivity)..."
    docker exec "$CONTAINER_NAME" nft delete table inet kill_switch 2>/dev/null
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
