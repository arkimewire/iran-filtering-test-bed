#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 5.1 Encapsulated Protocol Detection
# Uses DPI to detect and drop encapsulated protocols like VMess/VLess.
# Uses nftables queue + nfqueue Python daemon for hex-pattern inspection.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
SIGNATURE_FILE="config/backbone/encapsulated_signatures.conf"
QUEUE_NUM=5
DAEMON_SCRIPT="/opt/nfqueue-daemon.py"
PID_FILE="/var/run/nfqueue-encap.pid"

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip encap_proto_filter >/dev/null 2>&1; then
        echo "Encapsulated Protocol Detection is ON"
        docker exec "$CONTAINER_NAME" nft list table ip encap_proto_filter
    else
        echo "Encapsulated Protocol Detection is OFF"
    fi
}

on() {
    echo "Enabling Encapsulated Protocol Detection..."

    if docker exec "$CONTAINER_NAME" test -f "$PID_FILE" 2>/dev/null; then
        local old_pid
        old_pid=$(docker exec "$CONTAINER_NAME" cat "$PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$old_pid" 2>/dev/null
        sleep 0.3
    fi

    docker cp scripts/nfqueue-daemon.py "$CONTAINER_NAME:$DAEMON_SCRIPT"
    docker exec "$CONTAINER_NAME" mkdir -p /etc/nfqueue
    docker cp "$SIGNATURE_FILE" "$CONTAINER_NAME:/etc/nfqueue/encapsulated_signatures.conf"

    docker exec "$CONTAINER_NAME" bash -c \
        "python3 $DAEMON_SCRIPT $QUEUE_NUM &
         echo \$! > $PID_FILE"
    sleep 0.3

    docker exec "$CONTAINER_NAME" nft add table ip encap_proto_filter
    docker exec "$CONTAINER_NAME" nft "add chain ip encap_proto_filter forward { type filter hook forward priority filter; policy accept; }"
    nft_insert_priv_exemption "$CONTAINER_NAME" encap_proto_filter forward
    docker exec "$CONTAINER_NAME" nft add rule ip encap_proto_filter forward queue num $QUEUE_NUM

    echo "Done."
}

off() {
    echo "Disabling Encapsulated Protocol Detection..."

    docker exec "$CONTAINER_NAME" nft delete table ip encap_proto_filter 2>/dev/null

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
