#!/bin/bash

# 1.1 DNS Hijacking and Poisoning
# Redirects all DNS traffic to the local ISP DNS server.

CONTAINER_NAME="clab-iran-filtering-iran-isp"
INTERFACE="eth1" # Interface from iran-client

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
    docker exec "$CONTAINER_NAME" nft add rule ip dns_hijack prerouting iifname "$INTERFACE" udp dport 53 dnat to 10.0.1.1:53
    docker exec "$CONTAINER_NAME" nft add rule ip dns_hijack prerouting iifname "$INTERFACE" tcp dport 53 dnat to 10.0.1.1:53
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
