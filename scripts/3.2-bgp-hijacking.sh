#!/bin/bash

cd "$(dirname "$0")/.."

# 3.2 BGP Hijacking and Blackholing
# Simulates BGP hijacking by adding more specific routes to null.
#
# Architectural Note (Scenario 3 in AGENTS.md): 
# Instead of blackholing (dropping), the backbone can announce routes to 
# divert traffic into "Scrubbing Centers" (DPI clusters). In this simulation, 
# the iran-backbone node serves as both the routing chokepoint and the 
# scrubbing center.

CONTAINER_NAME="clab-iran-filtering-iran-backbone"
BLOCKLIST_FILE="config/backbone/bgp_hijack.conf"

get_prefixes() {
    if [ -f "$BLOCKLIST_FILE" ]; then
        grep -v '^#' "$BLOCKLIST_FILE" | grep -v '^[[:space:]]*$'
    else
        echo ""
    fi
}

status() {
    local active_hijacks
    active_hijacks=$(docker exec "$CONTAINER_NAME" ip route show | grep "blackhole")
    
    if [ -n "$active_hijacks" ]; then
        echo "BGP Hijacking (Blackholing) is ACTIVE for:"
        echo "$active_hijacks"
    else
        echo "BGP Hijacking (Blackholing) is OFF"
    fi
}

on() {
    echo "Enabling BGP Hijacking (Blackholing)..."
    local prefixes
    prefixes=$(get_prefixes)
    for prefix in $prefixes; do
        echo "  - Hijacking prefix: $prefix"
        docker exec "$CONTAINER_NAME" ip route add blackhole "$prefix" 2>/dev/null
    done
    echo "Done."
}

off() {
    echo "Disabling BGP Hijacking..."
    local prefixes
    prefixes=$(get_prefixes)
    for prefix in $prefixes; do
        docker exec "$CONTAINER_NAME" ip route del blackhole "$prefix" 2>/dev/null
    done
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
