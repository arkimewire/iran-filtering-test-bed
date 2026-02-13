#!/bin/bash
# Shared constants for all filtering scripts.

# Packet mark used by 7.2 (Tiered Access) to identify privileged traffic.
# All filtering scripts should check for this mark and accept early.
PRIV_MARK="0x10"

# Check if tiered access (7.2) is currently active by looking for the
# global_whitelist table on the backbone.
is_tiered_access_active() {
    local container="${1:-clab-iran-filtering-iran-backbone}"
    docker exec "$container" nft list table ip global_whitelist >/dev/null 2>&1
}

# Insert an nftables exemption rule at position 0 (top) of a given chain.
# Usage: nft_insert_priv_exemption <container> <table> <chain>
nft_insert_priv_exemption() {
    local container="$1" table="$2" chain="$3"
    docker exec "$container" nft insert rule ip "$table" "$chain" meta mark "$PRIV_MARK" accept 2>/dev/null
}
