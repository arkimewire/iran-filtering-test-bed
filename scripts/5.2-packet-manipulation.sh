#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 5.2 Packet Manipulation and Fragmentation Interference
#
# PRIMARY (TCP stream reassembly):
#   A transparent proxy intercepts port-443 traffic, reassembles the full
#   TCP stream, extracts the SNI, and blocks if matched.
#   Uses nftables REDIRECT (via nft nat) + Python proxy daemon.
#
# SECONDARY (IP fragment dropping):
#   nftables rules drop all non-initial IP fragments.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
INTERFACE="eth1"
PROXY_PORT=8443
PROXY_SCRIPT="/opt/sni-reassembly-proxy.py"
PROXY_PID_FILE="/var/run/sni-reassembly-proxy.pid"
BLOCKLIST_FILE="config/backbone/sni_blocklist.conf"

status() {
    local proxy_running=false
    local frag_blocking=false

    if docker exec "$CONTAINER_NAME" test -f "$PROXY_PID_FILE" 2>/dev/null; then
        local pid
        pid=$(docker exec "$CONTAINER_NAME" cat "$PROXY_PID_FILE" 2>/dev/null)
        if docker exec "$CONTAINER_NAME" kill -0 "$pid" 2>/dev/null; then
            proxy_running=true
        fi
    fi

    if docker exec "$CONTAINER_NAME" nft list table ip fragmentation_interference >/dev/null 2>&1; then
        frag_blocking=true
    fi

    if $proxy_running || $frag_blocking; then
        echo "Packet Manipulation is ON"
        $proxy_running && echo "  TCP Stream Reassembly Proxy: running (port $PROXY_PORT)"
        $frag_blocking && echo "  IP Fragment Blocking: active"
    else
        echo "Packet Manipulation is OFF"
    fi
}

on() {
    echo "Enabling Packet Manipulation..."

    # --- 1. TCP Stream Reassembly Proxy ---
    echo "  Starting TCP stream reassembly proxy..."

    # Kill any existing proxy (idempotency)
    if docker exec "$CONTAINER_NAME" test -f "$PROXY_PID_FILE" 2>/dev/null; then
        local old_pid
        old_pid=$(docker exec "$CONTAINER_NAME" cat "$PROXY_PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$old_pid" 2>/dev/null
        sleep 0.5
    fi

    # Copy the proxy script and blocklist into the container
    docker cp scripts/sni-reassembly-proxy.py "$CONTAINER_NAME:$PROXY_SCRIPT"
    docker cp "$BLOCKLIST_FILE" "$CONTAINER_NAME:/etc/sni_blocklist.conf"

    # Start the proxy daemon
    docker exec "$CONTAINER_NAME" bash -c \
        "python3 $PROXY_SCRIPT &
         echo \$! > $PROXY_PID_FILE"

    # Wait for proxy to start listening
    sleep 0.5

    # Redirect port 443 traffic to the proxy using nftables nat
    docker exec "$CONTAINER_NAME" nft add table ip pkt_manip_nat 2>/dev/null
    docker exec "$CONTAINER_NAME" nft "add chain ip pkt_manip_nat prerouting { type nat hook prerouting priority dstnat; policy accept; }" 2>/dev/null
    docker exec "$CONTAINER_NAME" nft add rule ip pkt_manip_nat prerouting iifname "$INTERFACE" tcp dport 443 redirect to :$PROXY_PORT

    # --- 2. IP Fragment Blocking ---
    echo "  Enabling IP fragment blocking..."
    docker exec "$CONTAINER_NAME" nft delete table ip fragmentation_interference 2>/dev/null || true
    docker exec "$CONTAINER_NAME" nft add table ip fragmentation_interference
    docker exec "$CONTAINER_NAME" nft "add chain ip fragmentation_interference forward { type filter hook forward priority filter; policy accept; }"
    nft_insert_priv_exemption "$CONTAINER_NAME" fragmentation_interference forward
    docker exec "$CONTAINER_NAME" nft add rule ip fragmentation_interference forward ip frag-off \& 0x3fff != 0 drop

    echo "Done."
}

off() {
    echo "Disabling Packet Manipulation..."

    # --- 1. Stop the proxy ---
    if docker exec "$CONTAINER_NAME" test -f "$PROXY_PID_FILE" 2>/dev/null; then
        local pid
        pid=$(docker exec "$CONTAINER_NAME" cat "$PROXY_PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$pid" 2>/dev/null
        docker exec "$CONTAINER_NAME" rm -f "$PROXY_PID_FILE" 2>/dev/null
    fi

    # Remove nftables nat rules
    docker exec "$CONTAINER_NAME" nft delete table ip pkt_manip_nat 2>/dev/null

    # --- 2. Remove IP fragment blocking ---
    docker exec "$CONTAINER_NAME" nft delete table ip fragmentation_interference 2>/dev/null

    echo "Done."
}

case "$1" in
    on) on ;;
    off) off ;;
    status) status ;;
    *) echo "Usage: $0 {on|off|status}"; exit 1 ;;
esac
