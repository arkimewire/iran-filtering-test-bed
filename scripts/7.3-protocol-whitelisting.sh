#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 7.3 Protocol Whitelisting (Default-Deny Posture)
# Blocks everything except a strict whitelist of protocols (DNS, HTTP, HTTPS).
# This is an escalation beyond blocking specific things; it blocks ALL by default.

CONTAINER_NAME=$(resolve_container BACKBONE)

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip protocol_whitelisting >/dev/null 2>&1; then
        echo "Protocol Whitelisting is ON (Default-Deny Active)"
        docker exec "$CONTAINER_NAME" nft list table ip protocol_whitelisting
    else
        echo "Protocol Whitelisting is OFF"
    fi
}

on() {
    echo "Enabling Protocol Whitelisting (Escalated Default-Deny posture)..."
    
    docker exec "$CONTAINER_NAME" nft add table ip protocol_whitelisting
    echo "  - Setting default FORWARD policy to DROP..."
    docker exec "$CONTAINER_NAME" nft add chain ip protocol_whitelisting forward '{ type filter hook forward priority filter; policy drop; }'
    
    # If tiered access (7.2) is active, exempt privileged IPs from default-deny
    if is_tiered_access_active "$CONTAINER_NAME"; then
        echo "  - Tiered access detected: exempting privileged IPs (mark $PRIV_MARK)..."
        nft_insert_priv_exemption "$CONTAINER_NAME" protocol_whitelisting forward
    fi

    docker exec "$CONTAINER_NAME" nft add rule ip protocol_whitelisting forward ct state established,related accept

    echo "  - Whitelisting DNS (UDP/TCP 53)..."
    docker exec "$CONTAINER_NAME" nft add rule ip protocol_whitelisting forward udp dport 53 accept
    docker exec "$CONTAINER_NAME" nft add rule ip protocol_whitelisting forward tcp dport 53 accept
    
    echo "  - Whitelisting HTTP (TCP 80)..."
    docker exec "$CONTAINER_NAME" nft add rule ip protocol_whitelisting forward tcp dport 80 accept
    
    echo "  - Whitelisting HTTPS (TCP 443)..."
    docker exec "$CONTAINER_NAME" nft add rule ip protocol_whitelisting forward tcp dport 443 accept

    echo "  - Whitelisting ICMP (Ping)..."
    docker exec "$CONTAINER_NAME" nft add rule ip protocol_whitelisting forward icmp type echo-request accept

    echo "Done. All non-whitelisted traffic is now dropped at the backbone."
}

off() {
    echo "Disabling Protocol Whitelisting..."
    docker exec "$CONTAINER_NAME" nft delete table ip protocol_whitelisting 2>/dev/null
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
