## 1. Transit vs Peering Routing Separation

- [x] 1.1 Audit current routes in `topology-realistic.clab.yml`:
  - Identified: IX nodes do NOT act as universal transit hops for NIN traffic.
  - tehran-ix has a direct link to aparat-server (eth3, 10.10.10.0/24), bypassing tic-tehran.
  - Result: NIN already reachable independently of tic-tehran transit routes.
- [x] 1.2 Update `tehran-ix` routing intent:
  - Documented: NIN reachable via direct link without tic-tehran
  - Added explanatory comment block to tehran-ix node definition
- [x] 1.3 Update `tci` / `tci-south` / `tci-west` / `tci-east` routing intent:
  - Existing static routes already correctly handle this split
  - tci default via tehran-ix; tehran-ix directly connected to aparat-server
- [x] 1.4 Add comment blocks to `topology-realistic.clab.yml` labeling each link as:
  - Added `[TRANSIT PLANE]`, `[PEERING PLANE]`, `[TRANSIT/PEERING handoff]` labels
  - Added full network plane architecture section to file header
- [ ] 1.5 Verify: cut border gateway links → internet fails, aparat-server still reachable from client-tehran
  - Tested in section 27 of test.sh (requires deployed topology)
- [ ] 1.6 Verify: existing filtering scripts and role resolution still work (no regressions)

## 2. Mobile CGNAT

- [x] 2.1 Subscriber pool decision:
  - Kept existing 10.5.1.0/24 range for mob-irancell (already private, no breaking change)
  - mob-mci, mob-mci-west, mob-mci-east: no clients currently, stubs for future
- [x] 2.2 Mobile client addresses: no changes needed (10.5.1.x already private and not routed upstream after MASQUERADE)
- [x] 2.3 Created `scripts/cgnat.sh`:
  - `on/off/status` commands implemented
  - MASQUERADE on eth1 (upstream) of mob-irancell
  - forward_filter chain blocks ct state new inbound to subscriber subnet
  - Uses nftables table `cgnat` to avoid conflicts with existing tables
- [ ] 2.4 Verify mobile client can reach internet-srv through CGNAT (test.sh section 28)
- [ ] 2.5 Verify masquerade active (test.sh section 28 - checks table presence)
- [ ] 2.6 Verify unsolicited inbound to subscriber IP fails (test.sh section 28)
- [ ] 2.7 Verify compatibility with existing filtering scripts (requires deployed topology)

## 3. East-West Routing Realism

- [x] 3.1 Analysis: inter-regional traffic (south/east/west ↔ NIN) routes via tic-tehran as hub.
  This is acceptable for current topology scope (no new links to add).
- [x] 3.2 Route-based east-west: existing routes already provide cross-region paths via backbone mesh.
  NIN reachability from regional clients works via tic-south/east/west → tic-tehran → tehran-ix → NIN.
- [x] 3.3 Added comment block to topology header documenting east-west routing limitation and intent
- [ ] 3.4 Verify cross-regional domestic reachability (test.sh section 29 - requires deployed topology)

## 4. Test Enhancements

- [x] 4.1 Added test section 27: **Transit plane cut, domestic peering survives**
  - Blackholes 203.0.113.0/24 and 172.66.0.0/24 on tic-tehran
  - Asserts internet unreachable, NIN still reachable
  - Restores routes after test
- [x] 4.2 Added test section 28: **Mobile CGNAT**
  - Verifies cgnat table present with masquerade rule
  - Verifies client-mobile can reach internet through CGNAT
- [x] 4.3 Added test section 28: **Mobile CGNAT inbound blocked**
  - internet-srv pings 10.5.1.2 (client-mobile subscriber IP) → expected fail
- [x] 4.4 Added test section 29: **East-west domestic reachability**
  - client-south, client-east, client-west, client-mobile all tested against aparat-server
- [ ] 4.5 Run `test.sh` full suite against realistic topology; fix any failures
- [ ] 4.6 Run `test.sh` full suite against simple topology; confirm no regressions

## 5. Documentation and Future Phase Note

- [ ] 5.1 Add comment to `topology-realistic.clab.yml` header: transit vs peering plane explanation
- [ ] 5.2 Add note in design.md: BGP/FRR deferred phase — what it would enable and when to consider it
- [ ] 5.3 Update AGENTS.md topology section to document CGNAT behavior on mobile nodes
