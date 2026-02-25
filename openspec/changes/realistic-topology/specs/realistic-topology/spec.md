## ADDED Requirements

### Requirement: Realistic topology file
The system SHALL provide a containerlab topology file `topology-realistic.clab.yml` with lab name `iran-realistic` that models Iran's actual internet architecture using ~16 nodes. All nodes SHALL use `kind: linux` (with `iran-sim:latest` image) for maximum performance and compatibility with nftables/iptables/tc/dnsmasq. No Android/mobile emulator nodes SHALL be included.

#### Scenario: Topology deploys successfully
- **WHEN** user runs `clab deploy -t topology-realistic.clab.yml`
- **THEN** all nodes start as running containers with prefix `clab-iran-realistic-`
- **AND** no errors are reported by containerlab

#### Scenario: Topology coexists with simple topology
- **WHEN** user has `iran-filtering` already deployed and deploys `iran-realistic`
- **THEN** both topologies run simultaneously without container name conflicts
- **AND** the simple topology containers (`clab-iran-filtering-*`) are unaffected

#### Scenario: Topology destroys cleanly
- **WHEN** user runs `clab destroy -t topology-realistic.clab.yml`
- **THEN** all `clab-iran-realistic-*` containers are removed
- **AND** the simple topology (if deployed) is unaffected

### Requirement: International layer with dual border gateways
The topology SHALL include two distinct border gateway nodes representing Iran's physical international cable entry points: `gw-falcon` (FALCON submarine cable, Bandar Abbas) and `gw-epeg` (EPEG terrestrial cable, Azerbaijan/Turkey border). Both SHALL connect to a shared `internet-srv` node on one side and to regional TIC nodes on the other.

#### Scenario: Dual-path international connectivity
- **WHEN** the topology is deployed and routing is configured
- **THEN** `client-tehran` can reach `internet-srv` via routes through both `gw-falcon` and `gw-epeg`
- **AND** traffic from `client-tehran` to `internet-srv` traverses `tic-tehran` then one of the border gateways (via regional nodes)

#### Scenario: Single border gateway failure
- **WHEN** the link between `tic-south` and `gw-falcon` is severed
- **THEN** traffic from `client-tehran` to `internet-srv` can still flow through `gw-epeg` via `tic-west`

### Requirement: TIC backbone hierarchy with regional nodes
The topology SHALL include a TIC core node (`tic-tehran`) and multiple regional backbone nodes (e.g., `tic-south`, `tic-west`, `tic-east`). `tic-tehran` SHALL be the central hub mesh-connected to regional nodes.

#### Scenario: Regional backbone provides provincial connectivity
- **WHEN** the topology is deployed
- **THEN** `client-province` reaches `internet-srv` via a path through a regional TIC node (`tic-south`) and then `tic-tehran`

#### Scenario: Regional shutdown isolates provincial users
- **WHEN** the link between `tic-tehran` and `tic-south` is severed
- **THEN** `client-province` (connected via `tic-south`) loses connectivity to `internet-srv`
- **AND** `client-tehran` retains full connectivity to `internet-srv`

### Requirement: Tehran IX for domestic traffic exchange
The topology SHALL include a `tehran-ix` node connected to `tic-tehran` and to `aparat-server` (domestic services). Tehran IX SHALL serve as the domestic peering point where NIN traffic is exchanged.

#### Scenario: Domestic services reachable via Tehran IX
- **WHEN** the topology is deployed
- **THEN** `client-tehran` can reach `aparat-server` via a path through `tehran-ix`

#### Scenario: Domestic services survive international shutdown
- **WHEN** all international links are severed (both border gateways disconnected)
- **THEN** `client-tehran` can still reach `aparat-server` via `tehran-ix`
- **AND** `client-tehran` cannot reach `internet-srv`

### Requirement: ISP and mobile operator diversity
The topology SHALL include distinct nodes for: `tci` (fixed-line wholesale, AS58224), `isp-shatel` (retail fixed ISP), `mob-mci` (MCI/Hamrah Aval mobile, AS197207), and `mob-irancell` (IranCell mobile, AS44244). These nodes SHALL represent the access layer between the backbone and end users.

#### Scenario: Tehran user routes through fixed-line ISP
- **WHEN** the topology is deployed
- **THEN** `client-tehran` reaches `internet-srv` via `isp-shatel` -> `tci` -> `tehran-ix` -> `tic-tehran`

#### Scenario: Provincial user routes through mobile operator
- **WHEN** the topology is deployed
- **THEN** `client-province` reaches `internet-srv` via `mob-irancell` -> regional TIC node -> `tic-tehran`

### Requirement: IPM academic gateway
The topology SHALL include an `ipm-academic` node (representing AS6736) with a separate link to `tic-tehran`, representing the independent academic gateway to the international internet.

#### Scenario: Academic network has independent path
- **WHEN** the topology is deployed
- **THEN** `ipm-academic` can reach `internet-srv` via `tic-tehran`

#### Scenario: Academic network whitelisted during shutdown
- **WHEN** the kill switch is activated on `tic-tehran` but the `ipm-academic` link is exempt
- **THEN** `ipm-academic` retains connectivity to `internet-srv`
- **AND** `client-tehran` loses connectivity to `internet-srv`

### Requirement: End-to-end routing and real internet access
All nodes in the topology SHALL have correct static routes so that traffic flows through the intended hierarchy. The backbone (`tic-tehran`) SHALL have NAT/MASQUERADE on its Docker bridge interface (`eth0`) so that clients can reach real-world internet services (e.g., google.com), matching the simple topology's behavior.

#### Scenario: Client can reach real internet
- **WHEN** the topology is deployed with no filtering active
- **THEN** `client-tehran` can ping `1.1.1.1` (real internet)
- **AND** `client-tehran` can ping `internet-srv` (simulated internet)

#### Scenario: Full chain connectivity
- **WHEN** the topology is deployed
- **THEN** `client-tehran` can ping every intermediate node in order: `isp-shatel`, `tci`, `tehran-ix`, `tic-tehran`, `tic-south`, `gw-falcon`, `internet-srv`

### Requirement: IP addressing scheme
The topology SHALL use a documented, non-overlapping IP addressing scheme. The scheme SHALL use `203.0.113.0/24` for the international segment (matching the simple topology) and `10.x.x.x/24` subnets for internal segments. Each point-to-point link SHALL have its own /24 subnet.

#### Scenario: No IP conflicts
- **WHEN** the topology is deployed
- **THEN** no two interfaces on different nodes share the same IP address
- **AND** every link endpoint pair is in the same /24 subnet

### Requirement: No mobile emulator nodes
The topology SHALL NOT include Android emulator nodes (redroid), scrcpy-web nodes, or any `IRAN_MOBILE` conditional logic. Mobile network operators (MCI, IranCell) SHALL be present as `linux` nodes.

#### Scenario: No mobile-specific containers
- **WHEN** the topology is deployed
- **THEN** no container with image `redroid/*` or `shmayro/scrcpy-web*` is created
- **AND** nodes `mob-mci` and `mob-irancell` are `linux` kind

### Requirement: Containerlab node kind assignments
All nodes in the realistic topology SHALL use `kind: linux` with the `iran-sim:latest` image. This ensures uniform support for nftables, iptables, tc, and dnsmasq across the entire network, facilitating filtering simulation at any node.

#### Scenario: Filtering scripts target any node
- **WHEN** any filtering script is executed
- **THEN** it can successfully run networking commands via `docker exec` against any node in the topology
- **AND** performance remains optimal due to the lightweight nature of the linux kind.
