#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 6.3 Dynamic IP Reputation System (Whitelist/Graylist/Blacklist)
# A multi-tiered reputation system for destination IPs.
# Uses nftables to handle different levels of interference.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
REPUTATION_FILE="config/backbone/ip_reputation.conf"

get_ips() {
    local type=$1
    if [ -f "$REPUTATION_FILE" ]; then
        # Format is type:IP
        grep "^$type:" "$REPUTATION_FILE" | cut -d':' -f2 | cut -d' ' -f1 | xargs | sed 's/ /, /g'
    else
        echo ""
    fi
}

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip ip_reputation >/dev/null 2>&1; then
        echo "Dynamic IP Reputation System is ON"
        docker exec "$CONTAINER_NAME" nft list table ip ip_reputation
    else
        echo "Dynamic IP Reputation System is OFF"
    fi
}

on() {
    echo "Enabling Dynamic IP Reputation System..."
    
    docker exec "$CONTAINER_NAME" nft add table ip ip_reputation
    docker exec "$CONTAINER_NAME" nft add chain ip ip_reputation forward '{ type filter hook forward priority filter; policy accept; }'
    nft_insert_priv_exemption "$CONTAINER_NAME" ip_reputation forward
    
    # 1. Whitelist (Core infrastructure)
    local whitelist_ips
    whitelist_ips=$(get_ips "whitelist")
    if [ -n "$whitelist_ips" ]; then
        echo "  - Whitelisted: $whitelist_ips"
        docker exec "$CONTAINER_NAME" nft add set ip ip_reputation whitelist '{ type ipv4_addr; flags interval; }'
        docker exec "$CONTAINER_NAME" nft add element ip ip_reputation whitelist "{ $whitelist_ips }"
        docker exec "$CONTAINER_NAME" nft add rule ip ip_reputation forward ip daddr @whitelist accept
        docker exec "$CONTAINER_NAME" nft add rule ip ip_reputation forward ip saddr @whitelist accept
    fi
    
    # 2. Blacklist (Confirmed VPN nodes)
    local blacklist_ips
    blacklist_ips=$(get_ips "blacklist")
    if [ -n "$blacklist_ips" ]; then
        echo "  - Blacklisted: $blacklist_ips"
        docker exec "$CONTAINER_NAME" nft add set ip ip_reputation blacklist '{ type ipv4_addr; flags interval; }'
        docker exec "$CONTAINER_NAME" nft add element ip ip_reputation blacklist "{ $blacklist_ips }"
        docker exec "$CONTAINER_NAME" nft add rule ip ip_reputation forward ip daddr @blacklist drop
        docker exec "$CONTAINER_NAME" nft add rule ip ip_reputation forward ip saddr @blacklist drop
    fi
    
    # 3. Graylist (Suspicious nodes: throttled and intermittently blocked)
    local graylist_ips
    graylist_ips=$(get_ips "graylist")
    if [ -n "$graylist_ips" ]; then
        echo "  - Graylisted (Throttled/Intermittent Block): $graylist_ips"
        docker exec "$CONTAINER_NAME" nft add set ip ip_reputation graylist '{ type ipv4_addr; flags interval; }'
        docker exec "$CONTAINER_NAME" nft add element ip ip_reputation graylist "{ $graylist_ips }"
        # Throttle and randomly drop graylisted IPs
        docker exec "$CONTAINER_NAME" nft add rule ip ip_reputation forward ip daddr @graylist limit rate over 100/second burst 50 packets drop
        docker exec "$CONTAINER_NAME" nft add rule ip ip_reputation forward ip daddr @graylist numgen random mod 100 \< 10 drop
    fi

    echo "Done."
}

off() {
    echo "Disabling Dynamic IP Reputation System..."
    docker exec "$CONTAINER_NAME" nft delete table ip ip_reputation 2>/dev/null
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
