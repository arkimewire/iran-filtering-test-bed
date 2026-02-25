#!/bin/bash

# 1.1 DNS Hijacking and Poisoning
# Redirects all DNS traffic to the local ISP DNS server.

source "$(dirname "$0")/common.sh"
CONTAINER_NAME=$(resolve_container ISP)
INTERFACE=$(resolve_interface ISP client)
ISP_DNS=$(resolve_ip ISP dns)

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip dns_hijack >/dev/null 2>&1; then
        echo "DNS Hijacking is ON"
    else
        echo "DNS Hijacking is OFF"
    fi
}

on() {
    echo "Enabling DNS Hijacking..."
    docker exec "$CONTAINER_NAME" nft add table ip dns_hijack
    docker exec "$CONTAINER_NAME" nft add chain ip dns_hijack prerouting '{ type nat hook prerouting priority dstnat; policy accept; }'
    docker exec "$CONTAINER_NAME" nft add rule ip dns_hijack prerouting iifname "$INTERFACE" udp dport 53 dnat to "${ISP_DNS}:53"
    docker exec "$CONTAINER_NAME" nft add rule ip dns_hijack prerouting iifname "$INTERFACE" tcp dport 53 dnat to "${ISP_DNS}:53"
    echo "Done."
}

off() {
    echo "Disabling DNS Hijacking..."
    docker exec "$CONTAINER_NAME" nft delete table ip dns_hijack 2>/dev/null
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
