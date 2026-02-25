#!/bin/bash
# Shared constants and topology abstraction for all filtering scripts.

# Packet mark used by 7.2 (Tiered Access) to identify privileged traffic.
PRIV_MARK="0x10"

# ── Topology Detection ─────────────────────────────────────────────
# Determines which topology is deployed. Supports IRAN_TOPOLOGY env var override.

detect_topology() {
    if [ -n "${IRAN_TOPOLOGY:-}" ]; then
        echo "$IRAN_TOPOLOGY"
        return 0
    fi
    if docker inspect --format '{{.State.Running}}' clab-iran-realistic-tic-tehran &>/dev/null; then
        echo "realistic"
    elif docker inspect --format '{{.State.Running}}' clab-iran-filtering-tic-tehran &>/dev/null; then
        echo "simple"
    else
        echo "ERROR: No topology detected. Deploy a topology first." >&2
        return 1
    fi
}

TOPOLOGY=$(detect_topology 2>/dev/null) || TOPOLOGY="simple"

case "$TOPOLOGY" in
    realistic) CLAB_PREFIX="clab-iran-realistic" ;;
    *)         CLAB_PREFIX="clab-iran-filtering" ;;
esac

# ── Container Resolution ───────────────────────────────────────────
# Maps abstract roles to container names per topology.

resolve_container() {
    local role="$1"
    case "$TOPOLOGY" in
        realistic)
            case "$role" in
                BACKBONE)      echo "${CLAB_PREFIX}-tic-tehran" ;;
                ISP)           echo "${CLAB_PREFIX}-isp-shatel" ;;
                IXP)           echo "${CLAB_PREFIX}-tehran-ix" ;;
                CLIENT)        echo "${CLAB_PREFIX}-client-tehran" ;;
                INTERNET_SRV)  echo "${CLAB_PREFIX}-internet-srv" ;;
                INTRANET)      echo "${CLAB_PREFIX}-aparat-server" ;;
                *) echo "ERROR: Unknown role '$role'" >&2; return 1 ;;
            esac
            ;;
        *)
            case "$role" in
                BACKBONE)      echo "${CLAB_PREFIX}-tic-tehran" ;;
                ISP)           echo "${CLAB_PREFIX}-isp-shatel" ;;
                IXP)           echo "${CLAB_PREFIX}-tehran-ix" ;;
                CLIENT)        echo "${CLAB_PREFIX}-iran-client" ;;
                INTERNET_SRV)  echo "${CLAB_PREFIX}-internet-srv" ;;
                INTRANET)      echo "${CLAB_PREFIX}-aparat-server" ;;
                *) echo "ERROR: Unknown role '$role'" >&2; return 1 ;;
            esac
            ;;
    esac
}

# ── Interface Resolution ───────────────────────────────────────────
# Maps role + direction to the correct interface name.
#   "internal"  = toward downstream (IXP/ISPs/clients)
#   "external"  = toward upstream (internet/border gateways)
#   "client"    = toward directly-connected client
#   "isp"       = IXP interface toward ISP (kill switch)

resolve_interface() {
    local role="$1" direction="$2"
    case "$TOPOLOGY" in
        realistic)
            case "${role}:${direction}" in
                BACKBONE:internal)  echo "eth4" ;;  # tic-tehran toward tehran-ix
                BACKBONE:external)  echo "eth1" ;;  # tic-tehran toward tic-south (primary international via FALCON)
                ISP:client)         echo "eth1" ;;  # isp-shatel toward client-tehran
                ISP:external)       echo "eth2" ;;  # isp-shatel toward tci
                IXP:isp)            echo "eth2" ;;  # tehran-ix toward tci (bridge port)
                *) echo "ERROR: Unknown interface '${role}:${direction}'" >&2; return 1 ;;
            esac
            ;;
        *)
            case "${role}:${direction}" in
                BACKBONE:internal)  echo "eth1" ;;  # tic-tehran toward tehran-ix
                BACKBONE:external)  echo "eth2" ;;  # tic-tehran toward internet-srv
                ISP:client)         echo "eth1" ;;  # isp-shatel toward iran-client
                ISP:external)       echo "eth2" ;;  # isp-shatel toward tehran-ix
                IXP:isp)            echo "eth1" ;;  # tehran-ix toward isp-shatel
                *) echo "ERROR: Unknown interface '${role}:${direction}'" >&2; return 1 ;;
            esac
            ;;
    esac
}

# ── IP Resolution ──────────────────────────────────────────────────
# Maps role + context to IP addresses used in filtering rules and tests.

resolve_ip() {
    local role="$1" context="$2"
    case "$TOPOLOGY" in
        realistic)
            case "${role}:${context}" in
                ISP:self)           echo "10.0.1.1" ;;
                ISP:dns)            echo "10.0.1.1" ;;
                CLIENT:self)        echo "10.0.1.2" ;;
                INTERNET_SRV:self)  echo "203.0.113.2" ;;
                INTRANET:self)      echo "10.10.10.2" ;;
                BACKBONE:self)      echo "10.2.1.1" ;;
                BACKBONE:dns)       echo "10.2.1.1" ;;
                *) echo "ERROR: Unknown IP '${role}:${context}'" >&2; return 1 ;;
            esac
            ;;
        *)
            case "${role}:${context}" in
                ISP:self)           echo "10.0.1.1" ;;
                ISP:dns)            echo "10.0.1.1" ;;
                CLIENT:self)        echo "10.0.1.2" ;;
                INTERNET_SRV:self)  echo "203.0.113.2" ;;
                INTRANET:self)      echo "10.10.10.2" ;;
                BACKBONE:self)      echo "10.0.3.1" ;;
                BACKBONE:dns)       echo "10.0.3.1" ;;
                *) echo "ERROR: Unknown IP '${role}:${context}'" >&2; return 1 ;;
            esac
            ;;
    esac
}

# ── Node List ──────────────────────────────────────────────────────
# Returns all node names for the active topology (used by test.sh health checks).

topology_nodes() {
    case "$TOPOLOGY" in
        realistic)
            echo "internet-srv gw-falcon gw-epeg tic-tehran tic-south tic-west tic-east tehran-ix tci isp-shatel mob-mci ipm-academic client-tehran aparat-server isfahan-ix tci-south isp-south mob-irancell client-south client-province tabriz-ix tci-west isp-west mob-mci-west client-west mashhad-ix tci-east isp-east mob-mci-east client-east"
            ;;
        *)
            echo "iran-client isp-shatel tehran-ix tic-tehran internet-srv aparat-server"
            ;;
    esac
}

# ── Helper Functions ───────────────────────────────────────────────

is_tiered_access_active() {
    local container="${1:-$(resolve_container BACKBONE)}"
    docker exec "$container" nft list table ip global_whitelist >/dev/null 2>&1
}

nft_insert_priv_exemption() {
    local container="$1" table="$2" chain="$3"
    docker exec "$container" nft insert rule ip "$table" "$chain" meta mark "$PRIV_MARK" accept 2>/dev/null
}
