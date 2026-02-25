## Why

The current realistic topology (`topology-realistic.clab.yml`) is architecturally strong but conflates two distinct network roles:

1. **International transit paths** (ISP → TIC → border gateways → internet)
2. **Domestic peering paths** (networks ↔ IX ↔ NIN/local content)

As a result, IX nodes appear as mandatory transit chokepoints rather than domestic exchange fabric, which leads to unrealistic shutdown simulation behavior. A total international blackout should keep domestic/NIN traffic alive via the peering plane; currently the topology does not cleanly model this.

Additionally, mobile operator nodes (`mob-mci`, `mob-irancell`, etc.) behave as plain routers, missing a critical real-world property: mobile subscribers in Iran are behind **CGNAT** (Carrier-Grade NAT). This directly affects how VPN protocols behave — UDP hole-punching fails, inbound connections are blocked, NAT mapping timeouts disrupt long-lived tunnels.

Finally, the backbone is fairly north-south; adding minimal east-west structural realism allows simulation of regional routing behavior.

**BGP is explicitly deferred** — the complexity/benefit ratio is unfavorable at this stage. Static routing remains.

## What Changes

1. **Transit vs Peering Path Separation**
   - International prefixes route via the TIC transit plane (TIC nodes → border gateways)
   - Domestic/NIN prefixes prefer IX peering paths
   - Shutdown of transit plane (border gateway links) leaves domestic reachable
   - Documented with clear comments in the topology file

2. **Mobile CGNAT**
   - CGNAT (nftables MASQUERADE) applied on all `mob-*` nodes
   - Subscriber-side uses private RFC1918 subscriber pools; upstream is the routable lab range
   - Unsolicited inbound connections to mobile subscribers blocked by default
   - `scripts/cgnat.sh` with `on/off/status` commands consistent with existing script style

3. **Targeted East-West Realism**
   - One or two minimal regional domestic cross-paths added
   - East-west domestic traffic avoids mandatory hairpin through central node
   - No full mesh; topology size stays bounded

4. **Test Enhancements**
   - Test: international transit down, domestic/NIN still alive
   - Test: mobile egress appears NATed on upstream side
   - Test: unsolicited inbound to mobile subscriber blocked
   - Test: east-west domestic reachability survives partial failure

## Non-Goals

- Replacing static routing with BGP/FRR (deferred)
- Full operator-specific policy emulation for all ISPs
- Android mobile node support (separate change)
- Modifying the simple topology (`topology.clab.yml`)
