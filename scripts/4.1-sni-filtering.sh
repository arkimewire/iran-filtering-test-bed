#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 4.1 SNI (Server Name Indication) Discovery
# Inspects TLS ClientHello SNI fields to drop connections.
# Uses nftables queue + nfqueue Python daemon for payload inspection.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
BLOCKLIST_FILE="config/backbone/sni_blocklist.conf"
QUEUE_NUM=2
DAEMON_SCRIPT="/opt/nfqueue-daemon.py"
PID_FILE="/var/run/nfqueue-sni.pid"

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip sni_filter >/dev/null 2>&1; then
        echo "SNI Filtering is ON"
        docker exec "$CONTAINER_NAME" nft list table ip sni_filter
    else
        echo "SNI Filtering is OFF"
    fi
}

on() {
    echo "Enabling SNI Filtering..."

    if docker exec "$CONTAINER_NAME" test -f "$PID_FILE" 2>/dev/null; then
        local old_pid
        old_pid=$(docker exec "$CONTAINER_NAME" cat "$PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$old_pid" 2>/dev/null
        sleep 0.3
    fi

    docker cp scripts/nfqueue-daemon.py "$CONTAINER_NAME:$DAEMON_SCRIPT"
    docker exec "$CONTAINER_NAME" mkdir -p /etc/nfqueue
    docker cp "$BLOCKLIST_FILE" "$CONTAINER_NAME:/etc/nfqueue/sni_blocklist.conf"

    docker exec "$CONTAINER_NAME" bash -c \
        "python3 $DAEMON_SCRIPT $QUEUE_NUM &
         echo \$! > $PID_FILE"
    sleep 0.3

    docker exec "$CONTAINER_NAME" nft add table ip sni_filter
    docker exec "$CONTAINER_NAME" nft "add chain ip sni_filter forward { type filter hook forward priority filter; policy accept; }"
    nft_insert_priv_exemption "$CONTAINER_NAME" sni_filter forward
    docker exec "$CONTAINER_NAME" nft add rule ip sni_filter forward tcp dport 443 queue num $QUEUE_NUM

    echo "Done."
}

off() {
    echo "Disabling SNI Filtering..."

    docker exec "$CONTAINER_NAME" nft delete table ip sni_filter 2>/dev/null

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
