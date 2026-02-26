## ADDED Requirements

### Requirement: Transit and peering paths are structurally distinct
The realistic topology routing SHALL distinguish between international transit paths (via TIC backbone to border gateways) and domestic peering paths (via IX to NIN/local services). These two planes SHALL be independently operable.

#### Scenario: International shutdown preserves domestic reachability
- **WHEN** all border gateway routes are removed or blackholed at the TIC level
- **THEN** `client-tehran` cannot reach `internet-srv` (203.0.113.2)
- **AND** `client-tehran` CAN still reach `aparat-server` (10.10.10.2) via the IX peering path
- **AND** no filtering scripts need to be toggled to achieve this

#### Scenario: Normal operation uses transit path for internet
- **WHEN** the topology is deployed with no restrictions
- **THEN** traffic from `client-tehran` to `internet-srv` passes through `tic-tehran` and a border gateway
- **AND** traffic from `client-tehran` to `aparat-server` passes through `tehran-ix`

#### Scenario: IX plane stays alive during transit cutoff
- **WHEN** `tic-tehran` routes toward `gw-falcon` and `gw-epeg` are removed
- **THEN** `tehran-ix` remains forwarding traffic between TCI and `aparat-server`
- **AND** `aparat-server` is reachable from `client-tehran` with latency under 10ms

### Requirement: Mobile operators implement CGNAT
All `mob-*` nodes in the realistic topology SHALL perform Carrier-Grade NAT (CGNAT) using nftables MASQUERADE. Mobile subscriber-facing subnets SHALL use private RFC1918 ranges. The upstream-facing interface SHALL present a single routable lab address.

#### Scenario: Mobile client reaches internet with NATed address
- **WHEN** CGNAT is enabled on `mob-irancell`
- **AND** `client-mobile` (on subscriber pool subnet) sends a packet to `internet-srv`
- **THEN** `internet-srv` sees source IP as the upstream-facing address of `mob-irancell`
- **AND** `client-mobile`'s original subscriber IP is NOT visible at `internet-srv`

#### Scenario: Unsolicited inbound connection to mobile subscriber fails
- **WHEN** CGNAT is enabled on `mob-irancell`
- **AND** an external host attempts to initiate a TCP connection directly to `client-mobile`'s subscriber IP
- **THEN** the connection fails (no route or DNAT)
- **AND** `client-mobile` receives no traffic from the attempt

#### Scenario: CGNAT is togglable without service disruption
- **WHEN** `scripts/cgnat.sh off` is run
- **THEN** CGNAT rules are removed from all `mob-*` nodes
- **AND** `client-mobile` can communicate using its subscriber IP directly (if routed)
- **WHEN** `scripts/cgnat.sh on` is run
- **THEN** CGNAT is restored

#### Scenario: Existing filtering mechanisms work through CGNAT
- **WHEN** CGNAT is enabled on `mob-irancell`
- **AND** a filtering mechanism (e.g., SNI filtering, DNS hijacking) is active on the backbone
- **THEN** filtering behavior is unchanged for traffic originating from `client-mobile`

### Requirement: East-west domestic reachability
Regional domestic traffic (between different regions) SHALL be routable via domestic paths without mandatory hairpin through the international transit plane.

#### Scenario: South region client reaches NIN domestically
- **WHEN** no international transit restrictions are active
- **THEN** `client-south` can reach `aparat-server` via `isfahan-ix` → `tehran-ix` path
- **AND** path does not depend on border gateway availability

#### Scenario: East region client reaches NIN domestically
- **WHEN** no international transit restrictions are active
- **THEN** `client-east` can reach `aparat-server` via `mashhad-ix` → `tehran-ix` path
- **AND** path does not depend on border gateway availability

### Requirement: CGNAT script interface
A script `scripts/cgnat.sh` SHALL be provided with `on`, `off`, and `status` commands following the existing filtering script conventions.

#### Scenario: cgnat.sh on activates CGNAT
- **WHEN** `docker exec <backbone-or-any-node> bash /scripts/cgnat.sh on` is run
- **THEN** nftables CGNAT rules are applied to all detected `mob-*` nodes
- **AND** `scripts/cgnat.sh status` reports CGNAT as active

#### Scenario: cgnat.sh off deactivates CGNAT
- **WHEN** `scripts/cgnat.sh off` is run
- **THEN** CGNAT nftables tables are deleted from all `mob-*` nodes
- **AND** `scripts/cgnat.sh status` reports CGNAT as inactive
