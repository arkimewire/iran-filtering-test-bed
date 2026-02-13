#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 7.2 Tiered Access and Whitelisting (The "National Information Network")
# Manages a whitelist of "privileged" IPs that bypass ALL filtering.
#
# Uses a high-priority nftables chain (priority -200) to mark packets from/to
# privileged IPs with meta mark 0x10. All filtering scripts check for this mark
# and accept early via "meta mark 0x10 accept" in their nftables chains.
#
# When 7.2 is enabled AFTER other filters, it injects exemption rules into
# all currently active nftables filtering tables/chains.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
WHITELIST_FILE="config/backbone/privileged_ips.conf"

# All nftables tables and their forward chains used by filtering scripts
NFT_TABLES=(
    "doh_dot_blocking:forward"
    "ip_blocking:forward"
    "fragmentation_interference:forward"
    "active_probing:forward"
    "behavioral_pattern:forward"
    "protocol_throttling:forward"
    "ip_reputation:forward"
    "protocol_whitelisting:forward"
    "http_host_filter:forward"
    "sni_filter:forward"
    "tls_fingerprint:forward"
    "sni_rst_filter:forward"
    "encap_proto_filter:forward"
)

get_privileged_ips() {
    if [ -f "$WHITELIST_FILE" ]; then
        grep -v '^#' "$WHITELIST_FILE" | grep -v '^[[:space:]]*$' | awk '{print $1}' | xargs | sed 's/ /, /g'
    else
        echo ""
    fi
}

inject_exemptions() {
    echo "  - Injecting exemptions into active filtering chains..."

    for entry in "${NFT_TABLES[@]}"; do
        local table="${entry%%:*}"
        local chain="${entry##*:}"
        if docker exec "$CONTAINER_NAME" nft list table ip "$table" >/dev/null 2>&1; then
            nft_insert_priv_exemption "$CONTAINER_NAME" "$table" "$chain"
        fi
    done
}

remove_exemptions() {
    echo "  - Removing exemptions from filtering chains..."

    for entry in "${NFT_TABLES[@]}"; do
        local table="${entry%%:*}"
        local chain="${entry##*:}"
        if docker exec "$CONTAINER_NAME" nft list table ip "$table" >/dev/null 2>&1; then
            local handle
            handle=$(docker exec "$CONTAINER_NAME" nft -a list chain ip "$table" "$chain" 2>/dev/null \
                | grep "meta mark $PRIV_MARK accept" | awk '{print $NF}')
            for h in $handle; do
                docker exec "$CONTAINER_NAME" nft delete rule ip "$table" "$chain" handle "$h" 2>/dev/null
            done
        fi
    done
}

status() {
    if docker exec "$CONTAINER_NAME" nft list set ip global_whitelist privileged_ips >/dev/null 2>&1; then
        echo "Tiered Access (Privileged Whitelist) is ACTIVE"
        docker exec "$CONTAINER_NAME" nft list table ip global_whitelist
    else
        echo "Tiered Access (Privileged Whitelist) is INACTIVE"
    fi
}

on() {
    local ips
    ips=$(get_privileged_ips)

    echo "Enabling Tiered Access..."
    docker exec "$CONTAINER_NAME" nft add table ip global_whitelist
    docker exec "$CONTAINER_NAME" nft add set ip global_whitelist privileged_ips '{ type ipv4_addr; flags interval; }'

    docker exec "$CONTAINER_NAME" nft "add chain ip global_whitelist bypass { type filter hook forward priority -200; policy accept; }"

    if [ -n "$ips" ]; then
        echo "  - Adding privileged IPs: $ips"
        docker exec "$CONTAINER_NAME" nft add element ip global_whitelist privileged_ips "{ $ips }"
        docker exec "$CONTAINER_NAME" nft add rule ip global_whitelist bypass ip saddr @privileged_ips meta mark set "$PRIV_MARK"
        docker exec "$CONTAINER_NAME" nft add rule ip global_whitelist bypass ip daddr @privileged_ips meta mark set "$PRIV_MARK"
    else
        echo "  - Warning: No IPs found in $WHITELIST_FILE"
    fi

    inject_exemptions

    echo "Done."
}

off() {
    echo "Disabling Tiered Access..."
    remove_exemptions
    docker exec "$CONTAINER_NAME" nft delete table ip global_whitelist 2>/dev/null
    echo "Done."
}

case "$1" in
    on) on ;;
    off) off ;;
    status) status ;;
    *) echo "Usage: $0 {on|off|status}"; exit 1 ;;
esac
