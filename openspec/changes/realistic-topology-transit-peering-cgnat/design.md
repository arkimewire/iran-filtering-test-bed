## Context

The project has:
- a simple 6-node topology for mechanism-level filtering tests
- a realistic 30-node topology with regional TIC/IX/ISP nodes
- 20 filtering mechanisms with a comprehensive test suite
- role-based container resolution in `scripts/common.sh`

This change improves architectural semantics without breaking any existing behavior.

## Current Topology Analysis

### Current flow (all traffic)
```
client → ISP → wholesale (TCI) → IX → TIC backbone → border gateway → internet
                                  ↓
                               aparat-server
```

**Problem:** IX is in the mandatory transit path for all traffic including international. In reality:
- IX is for **domestic peering** (ISP ↔ content/NIN exchange)
- International transit bypasses IX or uses it only for policy reasons
- During shutdown, the TIC transit path is severed; the IX/peering plane should remain

### Intended flow model
```
                          [TRANSIT PLANE]
ISP/mobile → wholesale (TCI) → TIC backbone → border gateway → internet

                          [PEERING PLANE]
ISP/mobile → wholesale (TCI) → IX → aparat-server (domestic services)
                                   ↔ other ISPs (peering)
```

## Design Decisions

### D1: Keep static routing
Static routes remain. BGP/FRR phase deferred to a future change.
- Pros: deterministic, zero config complexity
- Cons: no route convergence simulation
- Mitigation: document BGP as future enhancement

### D2: Transit vs peering split implementation
Two approaches were considered:

**Option A (route-based, no new links):** Adjust routing tables so internet prefixes prefer TIC transit paths and domestic prefixes prefer peering paths. No topology structure changes needed.

**Option B (dual-link, structural):** Add separate physical links: one transit link (ISP→TCI→TIC) and one peering link (ISP→IX) per region. More realistic, but doubles node interfaces and routing complexity.

**Choice: Option A** — route-based separation is sufficient for censorship simulation purposes and avoids topology explosion. Comments in the file document the intended plane for each route/link.

This means adjusting routing in the current topology so that:
- Routes toward `203.0.113.0/24` (internet-srv) and via eth0 (Docker bridge / real internet) prefer the TIC transit path
- Routes toward `10.10.10.0/24` (aparat-server) use the IX path and survive if the transit path is isolated

### D3: Mobile CGNAT design
```
[client-mobile]   (e.g., 10.5.1.0/24 - subscriber pool)
         ↓
[mob-irancell]  ← CGNAT here (MASQUERADE on upstream interface)
         ↓
[tci-south / upstream] (sees routable lab address, e.g., 10.4.3.2)
```

CGNAT behavior:
- MASQUERADE on upstream-facing interface of each `mob-*` node
- No DNAT rules (no port forwarding to subscribers by default)
- Default conntrack timeout profile (can be tightened for aggressive NAT testing)
- CGNAT uses existing subscriber subnets (e.g., `10.5.1.0/24`) mapped to the `10.4.x.x` routable range

Implementation: `scripts/cgnat.sh` with standard on/off/status interface. Applies to all `mob-*` nodes detected in the active topology.

### D4: East-west increment
Currently, inter-regional domestic traffic (e.g., client-south ↔ client-west) must go through `tic-tehran`. In reality, some regional IX nodes may have bilateral peering or a shared peering fabric.

Minimal change: add commentary and optional static route paths between regional IX nodes for domestic prefixes. Does not add new physical links (to avoid topology complexity); achieves east-west intent via routing policy only.

### D5: Shutdown scenario intent
The transit vs peering split directly enables this key scenario:

```
# Simulate international shutdown:
# Remove/blackhole routes toward border gateways at TIC level
# Result: client-tehran cannot reach internet-srv
# But: client-tehran can still reach aparat-server via IX peering path
```

This matches the documented Jan 2026 shutdown behavior (domestic services stayed up while international transit was severed).

## Impact on Existing Mechanisms

- Filtering scripts: no change needed; they target BACKBONE/ISP roles which map to same nodes
- test.sh: new test cases added; existing tests unaffected
- 7.1 kill-switch: may need updated comments to reflect transit-plane intent
- CGNAT chains named `cgnat` to avoid conflict with existing nftables tables

## Rollout Plan

1. Transit/peering routing documentation and comment additions
2. CGNAT implementation on mob-* nodes
3. East-west routing intent (route-based, no new links)
4. New test cases
5. Full test run with both simple and realistic topologies

## BGP Deferred Phase (future)

When BGP is added:
- FRR daemons on `tic-*` and `gw-*` nodes
- Route withdrawal simulates TIC disconnecting from international peers
- This enables dynamic hijacking/flapping simulation (method 3.2)
- Not part of this change
