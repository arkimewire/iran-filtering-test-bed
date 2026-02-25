#!/bin/bash

# CGNAT - Carrier-Grade NAT for mobile operator nodes.
# Simulates the CGNAT behavior of Iranian mobile carriers (MCI, IranCell, etc.):
#   - Subscriber traffic is masqueraded at the upstream interface.
#     Upstream nodes see the operator's routable address, not the subscriber IP.
#   - Unsolicited inbound NEW connections to subscriber subnets are blocked.
#     Existing connections (subscriber-initiated) pass return traffic normally.
#
# Only applicable in the realistic topology.
# Currently targets mob-irancell (the only mob-* node with active subscribers).
# Other mob-* nodes (mob-mci, mob-mci-west, mob-mci-east) have no clients yet;
# they can be added here when subscriber clients are added to the topology.
#
# Usage: ./scripts/cgnat.sh {on|off|status}

cd "$(dirname "$0")/.."
source scripts/common.sh

if [ "$TOPOLOGY" != "realistic" ]; then
    echo "CGNAT is only applicable in the realistic topology (current: $TOPOLOGY)."
    exit 0
fi

CGNAT_TABLE="cgnat"

# Format: "container:upstream_iface:subscriber_cidr"
# upstream_iface: the interface facing upstream (where MASQUERADE is applied)
# subscriber_cidr: the subscriber IP pool behind this operator
MOBILE_NODES=(
    "${CLAB_PREFIX}-mob-irancell:eth1:10.5.1.0/24"
)

status() {
    local any_on=0
    for entry in "${MOBILE_NODES[@]}"; do
        local container="${entry%%:*}"
        local node_short="${container##*-}"
        if docker exec "$container" nft list table ip "$CGNAT_TABLE" >/dev/null 2>&1; then
            echo "CGNAT is ON for $node_short"
            docker exec "$container" nft list table ip "$CGNAT_TABLE"
            any_on=1
        else
            echo "CGNAT is OFF for $node_short"
        fi
    done
}

on() {
    echo "Enabling CGNAT on mobile operator nodes..."
    for entry in "${MOBILE_NODES[@]}"; do
        IFS=':' read -r container upstream_iface subscriber_cidr <<< "$entry"
        local node_short="${container##*-}"
        echo "  - $node_short: upstream=$upstream_iface, subscriber pool=$subscriber_cidr"

        # Idempotent: remove existing table first
        docker exec "$container" nft delete table ip "$CGNAT_TABLE" 2>/dev/null || true

        # NAT table: masquerade subscriber traffic on upstream interface
        docker exec "$container" nft add table ip "$CGNAT_TABLE"
        docker exec "$container" nft add chain ip "$CGNAT_TABLE" postrouting \
            '{ type nat hook postrouting priority srcnat; policy accept; }'
        docker exec "$container" nft add rule ip "$CGNAT_TABLE" postrouting \
            oifname "$upstream_iface" ip saddr "$subscriber_cidr" masquerade

        # Filter chain: block unsolicited inbound NEW connections to subscriber subnet
        # (simulates no port-forwarding / no DNAT by default on CGNAT)
        docker exec "$container" nft add chain ip "$CGNAT_TABLE" forward_filter \
            '{ type filter hook forward priority filter; policy accept; }'
        docker exec "$container" nft add rule ip "$CGNAT_TABLE" forward_filter \
            iifname "$upstream_iface" ip daddr "$subscriber_cidr" ct state new drop
    done
    echo "Done."
}

off() {
    echo "Disabling CGNAT on mobile operator nodes..."
    for entry in "${MOBILE_NODES[@]}"; do
        local container="${entry%%:*}"
        local node_short="${container##*-}"
        echo "  - $node_short"
        docker exec "$container" nft delete table ip "$CGNAT_TABLE" 2>/dev/null || true
    done
    echo "Done."
}

case "$1" in
    on)     on ;;
    off)    off ;;
    status) status ;;
    *)
        echo "Usage: $0 {on|off|status}"
        exit 1
        ;;
esac
