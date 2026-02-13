#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 1.2 DoH and DoT Blocking
# Blocks known public DoH/DoT providers (e.g., Cloudflare, Google) and port 853 (TCP/UDP).
# Also uses nfqueue DPI to detect ALPN 'dot' patterns and DNS provider SNI hostnames.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
CONFIG_FILE="config/backbone/doh_dot_providers.conf"
QUEUE_NUM=6
DAEMON_SCRIPT="/opt/nfqueue-daemon.py"
PID_FILE="/var/run/nfqueue-doh.pid"

get_provider_ips() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -v '^#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' | grep -v '^hostname:' | xargs | sed 's/ /, /g'
    else
        echo ""
    fi
}

status() {
    local nft_status="OFF"
    local dpi_status="OFF"

    if docker exec "$CONTAINER_NAME" nft list table ip doh_dot_blocking >/dev/null 2>&1; then
        nft_status="ON"
    fi

    if docker exec "$CONTAINER_NAME" test -f "$PID_FILE" 2>/dev/null; then
        local pid
        pid=$(docker exec "$CONTAINER_NAME" cat "$PID_FILE" 2>/dev/null)
        if docker exec "$CONTAINER_NAME" kill -0 "$pid" 2>/dev/null; then
            dpi_status="ON"
        fi
    fi

    echo "DoH/DoT Blocking: IP/Port 853 ($nft_status), DPI ALPN/SNI ($dpi_status)"

    if [ "$nft_status" == "ON" ]; then
        echo "--- nftables (L3/L4) ---"
        docker exec "$CONTAINER_NAME" nft list table ip doh_dot_blocking
    fi
}

on() {
    echo "Enabling DoH and DoT Blocking..."

    local DOH_DOT_IPS
    DOH_DOT_IPS=$(get_provider_ips)

    # 1. IP and Port Blocking (nftables)
    echo "  - Blocking port 853 (TCP/UDP) and known public DNS IPs (nftables)..."
    docker exec "$CONTAINER_NAME" nft add table ip doh_dot_blocking
    docker exec "$CONTAINER_NAME" nft add set ip doh_dot_blocking dns_providers '{ type ipv4_addr; }'
    if [ -n "$DOH_DOT_IPS" ]; then
        docker exec "$CONTAINER_NAME" nft add element ip doh_dot_blocking dns_providers "{ $DOH_DOT_IPS }"
    fi
    docker exec "$CONTAINER_NAME" nft "add chain ip doh_dot_blocking forward { type filter hook forward priority filter; policy accept; }"
    nft_insert_priv_exemption "$CONTAINER_NAME" doh_dot_blocking forward

    docker exec "$CONTAINER_NAME" nft add rule ip doh_dot_blocking forward meta l4proto { tcp, udp } th dport 853 drop
    docker exec "$CONTAINER_NAME" nft add rule ip doh_dot_blocking forward ip daddr @dns_providers drop
    docker exec "$CONTAINER_NAME" nft add rule ip doh_dot_blocking forward ip saddr @dns_providers drop

    # 2. DPI Simulation (nfqueue)
    echo "  - Enabling DPI: ALPN 'dot' detection and DNS provider SNI inspection..."

    if docker exec "$CONTAINER_NAME" test -f "$PID_FILE" 2>/dev/null; then
        local old_pid
        old_pid=$(docker exec "$CONTAINER_NAME" cat "$PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$old_pid" 2>/dev/null
        sleep 0.3
    fi

    docker cp scripts/nfqueue-daemon.py "$CONTAINER_NAME:$DAEMON_SCRIPT"
    docker exec "$CONTAINER_NAME" mkdir -p /etc/nfqueue
    docker cp "$CONFIG_FILE" "$CONTAINER_NAME:/etc/nfqueue/doh_dot_providers.conf"

    docker exec "$CONTAINER_NAME" bash -c \
        "python3 $DAEMON_SCRIPT $QUEUE_NUM &
         echo \$! > $PID_FILE"
    sleep 0.3

    docker exec "$CONTAINER_NAME" nft add rule ip doh_dot_blocking forward tcp dport 443 queue num $QUEUE_NUM

    echo "Done."
}

off() {
    echo "Disabling DoH and DoT Blocking..."
    docker exec "$CONTAINER_NAME" nft delete table ip doh_dot_blocking 2>/dev/null

    if docker exec "$CONTAINER_NAME" test -f "$PID_FILE" 2>/dev/null; then
        local pid
        pid=$(docker exec "$CONTAINER_NAME" cat "$PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$pid" 2>/dev/null
        docker exec "$CONTAINER_NAME" rm -f "$PID_FILE" 2>/dev/null
    fi

    echo "Done."
}

case "$1" in
    on) on ;;
    off) off ;;
    status) status ;;
    *) echo "Usage: $0 {on|off|status}"; exit 1 ;;
esac
