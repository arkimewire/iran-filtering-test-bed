#!/bin/bash

cd "$(dirname "$0")/.."
source scripts/common.sh

# 4.2 TLS Fingerprinting and Session Behavioral Analysis
# Identifies and blocks clients based on TLS handshake fingerprints (JA3/JA4).
# Uses nftables queue + nfqueue Python daemon for hex-pattern inspection.

CONTAINER_NAME=$(resolve_container BACKBONE)
SIGNATURE_FILE="config/backbone/tls_signatures.conf"
QUEUE_NUM=3
DAEMON_SCRIPT="/opt/nfqueue-daemon.py"
PID_FILE="/var/run/nfqueue-tlsfp.pid"

status() {
    if docker exec "$CONTAINER_NAME" nft list table ip tls_fingerprint >/dev/null 2>&1; then
        echo "TLS Fingerprinting is ON"
        docker exec "$CONTAINER_NAME" nft list table ip tls_fingerprint
    else
        echo "TLS Fingerprinting is OFF"
    fi
}

on() {
    echo "Enabling TLS Fingerprinting..."

    if docker exec "$CONTAINER_NAME" test -f "$PID_FILE" 2>/dev/null; then
        local old_pid
        old_pid=$(docker exec "$CONTAINER_NAME" cat "$PID_FILE" 2>/dev/null)
        docker exec "$CONTAINER_NAME" kill "$old_pid" 2>/dev/null
        sleep 0.3
    fi

    docker cp scripts/nfqueue-daemon.py "$CONTAINER_NAME:$DAEMON_SCRIPT"
    docker exec "$CONTAINER_NAME" mkdir -p /etc/nfqueue
    docker cp "$SIGNATURE_FILE" "$CONTAINER_NAME:/etc/nfqueue/tls_signatures.conf"

    docker exec "$CONTAINER_NAME" bash -c \
        "python3 $DAEMON_SCRIPT $QUEUE_NUM &
         echo \$! > $PID_FILE"
    sleep 0.3

    docker exec "$CONTAINER_NAME" nft add table ip tls_fingerprint
    docker exec "$CONTAINER_NAME" nft "add chain ip tls_fingerprint forward { type filter hook forward priority filter; policy accept; }"
    nft_insert_priv_exemption "$CONTAINER_NAME" tls_fingerprint forward
    docker exec "$CONTAINER_NAME" nft add rule ip tls_fingerprint forward tcp dport 443 queue num $QUEUE_NUM

    echo "Done."
}

off() {
    echo "Disabling TLS Fingerprinting..."

    docker exec "$CONTAINER_NAME" nft delete table ip tls_fingerprint 2>/dev/null

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
