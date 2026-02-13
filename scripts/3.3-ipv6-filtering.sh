#!/bin/bash

# 3.3 IPv6 Systematic Filtering
# Disables or filters IPv6 traffic at the backbone layer.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip6 ipv6_filter >/dev/null 2>&1; then
        echo "IPv6 Filtering is ON"
    else
        echo "IPv6 Filtering is OFF"
    fi
}

on() {
    echo "Enabling IPv6 Filtering (Dropping all IPv6 traffic)..."
    docker exec "$CONTAINER_NAME" nft add table ip6 ipv6_filter
    docker exec "$CONTAINER_NAME" nft add chain ip6 ipv6_filter forward '{ type filter hook forward priority filter; policy accept; }'
    docker exec "$CONTAINER_NAME" nft add rule ip6 ipv6_filter forward drop
    echo "Done."
}

off() {
    echo "Disabling IPv6 Filtering..."
    docker exec "$CONTAINER_NAME" nft delete table ip6 ipv6_filter 2>/dev/null
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
