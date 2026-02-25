#!/bin/bash

# 7.1 Total National Internet Shutdown (The "Kill Switch")
# Simple topology: severs IXP<->ISP link (drops on IXP interface toward ISP).
# Realistic topology: drops all forwarded traffic on TIC Tehran backbone
#   (simulates BGP route withdrawal at the national gateway level).

source "$(dirname "$0")/common.sh"

if [ "$TOPOLOGY" = "realistic" ]; then
    CONTAINER_NAME=$(resolve_container BACKBONE)
    KILL_MODE="backbone"
else
    CONTAINER_NAME=$(resolve_container IXP)
    INTERFACE=$(resolve_interface IXP isp)
    KILL_MODE="ixp"
fi

status() {
    if docker exec "$CONTAINER_NAME" nft list table inet kill_switch >/dev/null 2>&1; then
        echo "Kill Switch is ON (Internet is SHUT DOWN)"
        docker exec "$CONTAINER_NAME" nft list table inet kill_switch
    else
        echo "Kill Switch is OFF (Internet is ACTIVE)"
    fi
}

on() {
    docker exec "$CONTAINER_NAME" nft add table inet kill_switch
    docker exec "$CONTAINER_NAME" nft add chain inet kill_switch forward '{ type filter hook forward priority -100; policy accept; }'

    if [ "$KILL_MODE" = "backbone" ]; then
        echo "Activating Kill Switch (Dropping all forwarded traffic on backbone)..."
        docker exec "$CONTAINER_NAME" nft add rule inet kill_switch forward drop
    else
        echo "Activating Kill Switch (Severing IXP-ISP link)..."
        echo "  - Interface: $INTERFACE (Dropping all traffic)"
        docker exec "$CONTAINER_NAME" nft add rule inet kill_switch forward iifname "$INTERFACE" drop
        docker exec "$CONTAINER_NAME" nft add rule inet kill_switch forward oifname "$INTERFACE" drop
    fi
    
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
