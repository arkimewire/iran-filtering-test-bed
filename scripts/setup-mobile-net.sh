#!/bin/bash
# Configure eth1 networking for iran-mobile (redroid) container.
# Called by containerlab as a host exec stage after deployment.
# The overlay APK handles Android-side config (EthernetTracker);
# this script assigns the IP and policy route from the host namespace.
#
# Must wait for Android's netd to finish initializing policy rules,
# otherwise netd will overwrite our rule table on startup.

CONTAINER="clab-iran-filtering-iran-mobile"
IP="10.0.4.2/24"
GW="10.0.4.1"
TABLE=100
PRIO=5000

# Wait for container PID and eth1 link
for i in $(seq 1 30); do
    PID=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER" 2>/dev/null) || true
    if [ -n "$PID" ] && [ "$PID" != "0" ]; then
        if nsenter -t "$PID" -n ip link show eth1 &>/dev/null; then
            break
        fi
    fi
    sleep 1
done

if [ -z "$PID" ] || [ "$PID" = "0" ]; then
    echo "ERROR: container not running after 30s" >&2
    exit 1
fi

# Wait for Android boot completion (netd finishes during this phase)
for i in $(seq 1 60); do
    BOOT=$(docker exec "$CONTAINER" /system/bin/getprop sys.boot_completed 2>/dev/null || true)
    if [ "$BOOT" = "1" ]; then
        break
    fi
    sleep 1
done

# Extra delay for netd rule initialization to settle
sleep 3

# Re-read PID in case it changed
PID=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER" 2>/dev/null)

nsenter -t "$PID" -n ip addr add "$IP" dev eth1 2>/dev/null
nsenter -t "$PID" -n ip rule add from "${IP%/*}" table $TABLE prio $PRIO 2>/dev/null
nsenter -t "$PID" -n ip route add default via "$GW" dev eth1 table $TABLE onlink 2>/dev/null

echo "iran-mobile eth1 configured: $IP gw $GW"
