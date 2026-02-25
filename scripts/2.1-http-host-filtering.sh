#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 2.1 HTTP Host and URL Keyword Filtering
# Inspects HTTP Host headers to block connections.
# Uses nftables queue + nfqueue Python daemon for payload inspection.

CONTAINER_NAME=$(resolve_container BACKBONE)
BLOCKLIST_FILE="config/backbone/http_blocklist.conf"
QUEUE_NUM=1
DAEMON_SCRIPT="/opt/nfqueue-daemon.py"
PID_FILE="/var/run/nfqueue-http.pid"

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip http_host_filter >/dev/null 2>&1; then
        echo "HTTP Host Filtering is ON"
        docker exec "$CONTAINER_NAME" nft list table ip http_host_filter
    else
        echo "HTTP Host Filtering is OFF"
    fi
}

on() {
    echo "Enabling HTTP Host Filtering..."

    # Kill any existing daemon
    if docker exec "$CONTAINER_NAME" test -f "$PID_FILE" 2>/dev/null; then
        local old_pid
        old_pid=$(docker exec "$CONTAINER_NAME" cat "$PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$old_pid" 2>/dev/null
        sleep 0.3
    fi

    # Copy daemon and config into container
    docker cp scripts/nfqueue-daemon.py "$CONTAINER_NAME:$DAEMON_SCRIPT"
    docker exec "$CONTAINER_NAME" mkdir -p /etc/nfqueue
    docker cp "$BLOCKLIST_FILE" "$CONTAINER_NAME:/etc/nfqueue/http_blocklist.conf"

    # Start the nfqueue daemon
    docker exec "$CONTAINER_NAME" bash -c \
        "python3 $DAEMON_SCRIPT $QUEUE_NUM &
         echo \$! > $PID_FILE"
    sleep 0.3

    # Create nftables rules to queue HTTP traffic
    docker exec "$CONTAINER_NAME" nft add table ip http_host_filter
    docker exec "$CONTAINER_NAME" nft "add chain ip http_host_filter forward { type filter hook forward priority filter; policy accept; }"
    nft_insert_priv_exemption "$CONTAINER_NAME" http_host_filter forward
    docker exec "$CONTAINER_NAME" nft add rule ip http_host_filter forward tcp dport 80 queue num $QUEUE_NUM

    echo "Done."
}

off() {
    echo "Disabling HTTP Host Filtering..."

    docker exec "$CONTAINER_NAME" nft delete table ip http_host_filter 2>/dev/null

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
