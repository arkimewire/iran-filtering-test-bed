## Context

The project has a working 6-node simple topology (`topology.clab.yml`) with 20 filtering scripts and a comprehensive test suite. All scripts hardcode container names (e.g., `clab-iran-filtering-iran-backbone`) and interface names (e.g., `eth1`). The test suite (`test.sh`) similarly hardcodes the containerlab prefix `C="clab-iran-filtering"` and node names throughout.

We need to add a second ~15-node realistic topology that coexists with the simple one, while making all 20 existing scripts and the test suite work against both topologies without duplication.

## Goals / Non-Goals

**Goals:**
- Create `topology-realistic.clab.yml` with 16 nodes modeling Iran's actual internet architecture
- Use appropriate containerlab kinds: `nokia_srlinux` for pure-forwarding routers, `bridge` for the IXP, `linux` for filtering/testing nodes
- Make all 20 filtering scripts work on both topologies via auto-detection
- Make `test.sh` work on both topologies via auto-detection
- Preserve 100% backward compatibility with the simple topology
- Share config/blocklist files across topologies where filtering logic is identical

**Non-Goals:**
- Multi-node distributed filtering (e.g., running DPI on multiple backbone nodes simultaneously) -- all filtering still targets ONE backbone node per topology
- Android/mobile emulator support in the realistic topology
- Running both topologies simultaneously and testing cross-topology scenarios

## Decisions

### Decision 1: Topology file naming and containerlab lab name

**Choice:** `topology-realistic.clab.yml` with `name: iran-realistic`

**Rationale:** Follows the existing convention (`topology.clab.yml`). The `-realistic` suffix clearly communicates the purpose. Lab name `iran-realistic` gives container prefix `clab-iran-realistic-` which doesn't conflict with `clab-iran-filtering-`.

**Alternative considered:** `topology-full.clab.yml` -- rejected because "full" implies completeness which isn't the goal; "realistic" better conveys the design intent.

### Decision 2: Containerlab node kind assignments

**Choice:** All-linux approach for maximum performance and compatibility.

| Kind | Count | Nodes | Rationale |
|------|-------|-------|-----------|
| `linux` (iran-sim:latest) | 16 | All nodes | Provides full nftables/iptables/tc/dnsmasq compatibility. Lightweight operation compared to SR Linux. |

**Key constraint:** Every forwarding node in the realistic topology needs to support the filtering scripts (which use standard Linux networking tools). Keeping everything as `linux` ensures that `tic-tehran` and all regional backbone nodes can serve as targets for DPI and filtering simulations.

**Alternative considered:** Mixed-kind approach with `nokia_srlinux` and `bridge` -- rejected because SR Linux had significant performance impact on the host system and limited the nodes where filtering scripts could run.

### Decision 6: Containerlab interface naming and link ordering

In containerlab, interfaces are named `ethN` based on link order in the YAML file. All nodes use `ethN` since they are all `linux` kind. The link ordering in `topology-realistic.clab.yml` ensures that key nodes have predictable interface assignments:

**tic-tehran (backbone equivalent):**
- eth1: toward tic-south (link 5)
- eth2: toward tic-west (link 6)
- eth3: toward tic-east (link 7)
- eth4: toward tehran-ix (link 8)
- eth5: toward ipm-academic (link 9)

The "internal" interface for tc qdisc rules (bandwidth throttling, DBF) is eth4 (toward tehran-ix / downstream), matching the role of eth1 in the simple topology.

**isp-shatel (ISP equivalent):**
- eth1: toward client-tehran (link 17)
- eth2: toward tci (link 15)

**tehran-ix (IXP equivalent):**
- eth1: toward tic-tehran (link 8)
- eth2: toward tci (link 13)
- eth3: toward iran-nin (link 14)

### Decision 7: Kill switch behavior per topology

**Simple topology:** Kill switch on `iran-ixp` dropping traffic on `eth1` (IXP-ISP link). This is the existing behavior and won't change.

**Realistic topology:** Kill switch on `tic-tehran` dropping all forwarded traffic on the downstream-facing interfaces. This simulates BGP route withdrawal at the TIC level -- the architecturally correct location per Kentik/FilterWatch analysis.

The script detects topology and targets the correct node:
```bash
if [ "$TOPOLOGY" = "realistic" ]; then
    CONTAINER_NAME=$(resolve_container "BACKBONE")
    # Drop all forwarded traffic (simulates BGP withdrawal)
else
    CONTAINER_NAME=$(resolve_container "IXP")
    INTERFACE=$(resolve_interface "IXP" "isp")
fi
```

### Decision 8: Config file sharing strategy

**Shared (same files, both topologies):**
- `config/backbone/*.conf` -- all blocklists, signature files, reputation lists
- `config/isp/blocklist.conf` -- DNS blocklist

**Topology-specific (new files for realistic):**
- `config-realistic/tic-tehran/dnsmasq.conf` -- backbone DNS config
- `config-realistic/tic-tehran/nftables.conf` -- backbone base rules (NAT/masquerade)
- `config-realistic/isp-shatel/dnsmasq.conf` -- ISP DNS config
- `config-realistic/isp-shatel/nftables.conf` -- ISP base rules

The topology-specific configs handle node-specific IP addresses and interface names. The filtering blocklists are shared because the filtering *policy* is the same across topologies.

### Decision 9: test.sh refactoring approach

**Choice:** Replace the `run()` helper and `C` prefix with topology-aware versions:

```bash
source "$(dirname "$0")/scripts/common.sh"
TOPOLOGY=$(detect_topology)
echo "Detected topology: $TOPOLOGY"

C=$(echo "$CLAB_PREFIX")

# Role-based run helper
run_role() {
    local role="$1"; shift
    docker exec "$(resolve_container "$role")" bash -c "$*"
}

# Node-name run helper (for health checks)
run_node() {
    docker exec "${CLAB_PREFIX}-$1" bash -c "$2"
}
```

Health check nodes are listed per topology. Filtering tests use the same script invocations (scripts auto-detect). Assertion IPs use resolved values.

## Risks / Trade-offs

**[Risk] Detection race condition** -- If both topologies are deployed simultaneously, detection picks the first match (realistic takes priority).
→ **Mitigation:** `IRAN_TOPOLOGY` env var override. Document that testing one topology at a time is recommended.

**[Risk] Interface numbering fragility** -- Adding links to the realistic topology changes ethN assignments for existing nodes.
→ **Mitigation:** Document the link ordering requirement. Add a comment block in the YAML listing interface assignments.

**[Risk] tc qdisc on wrong interface** -- The bandwidth throttling and DBF scripts apply tc to a specific interface. If the interface mapping is wrong, throttling affects the wrong link direction.
→ **Mitigation:** `resolve_interface "BACKBONE" "internal"` is explicitly tested. The test suite verifies tc qdisc presence on the correct interface.

**[Risk] Increased test runtime** -- 15 nodes take longer to deploy and the test suite has more health checks.
→ **Mitigation:** Acceptable trade-off. The realistic topology is the "heavyweight" option by design.

## Migration Plan

1. **Phase 1 -- Abstraction layer (no new topology yet):**
   - Update `scripts/common.sh` with detection and resolution functions
   - Refactor all 20 scripts to use resolution (mechanical find-replace)
   - Refactor `test.sh` to use resolution
   - Run `test.sh` on simple topology -- must pass identically
   
2. **Phase 2 -- New topology:**
   - Create `topology-realistic.clab.yml` and `config-realistic/`
   - Deploy realistic topology
   - Run `test.sh` -- must pass on realistic topology

3. **Rollback:** If anything breaks, reverting the `common.sh` changes restores original behavior since all default values match the simple topology.

## Open Questions

1. **Provincial client routing:** Should `client-province` route through `mob-irancell` -> `tic-south` -> `tic-tehran` or through `mob-irancell` -> `tci` -> `tic-tehran`? Current design uses the former (regional backbone path). The choice affects whether regional shutdown tests work.
   → **Resolution:** Route through `tic-south` to enable regional shutdown simulation.

2. **DNS hijacking on multiple ISPs:** In the realistic topology, should `1.1-dns-hijacking.sh` apply to ALL ISP nodes (`isp-shatel`, `mob-mci`, `mob-irancell`) or just the primary one (`isp-shatel`)? Applying to all is more realistic but makes the script more complex.
   → **Resolution:** Apply to the primary ISP only (matching the single-ISP simple topology behavior). Multi-ISP filtering can be a future enhancement.

3. **Intranet reachability during kill switch:** In the simple topology, the kill switch cuts the IXP-ISP link, blocking both internet AND intranet. In the realistic topology, the kill switch at TIC level should block international traffic but could preserve domestic (via tehran-ix). Should the realistic kill switch also block intranet access to match the simple topology's test expectations?
   → **Resolution:** The realistic kill switch SHALL block all forwarded traffic through the backbone (both international and downstream), matching the simple topology test expectations. A separate "selective shutdown" script could be added later to simulate international-only cutoff.
