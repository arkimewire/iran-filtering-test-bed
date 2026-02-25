## ADDED Requirements

### Requirement: Topology auto-detection
`scripts/common.sh` SHALL provide a `detect_topology()` function that determines which topology is currently deployed by checking for the existence of known containers. It SHALL return `"simple"` if `clab-iran-filtering-iran-backbone` exists, `"realistic"` if `clab-iran-realistic-tic-tehran` exists, or fail with an error if neither is found.

#### Scenario: Simple topology detected
- **WHEN** the simple topology is deployed (containers `clab-iran-filtering-*` exist)
- **THEN** `detect_topology` returns `"simple"`

#### Scenario: Realistic topology detected
- **WHEN** the realistic topology is deployed (containers `clab-iran-realistic-*` exist)
- **THEN** `detect_topology` returns `"realistic"`

#### Scenario: No topology deployed
- **WHEN** no containerlab topology is running
- **THEN** `detect_topology` exits with a non-zero status and prints an error message

### Requirement: Role-based container resolution
`scripts/common.sh` SHALL provide a `resolve_container(role)` function that maps an abstract role name to the full container name for the active topology. The supported roles SHALL be: `BACKBONE`, `ISP`, `IXP`, `CLIENT`, `INTERNET_SRV`, `INTRANET`.

#### Scenario: Resolve backbone in simple topology
- **WHEN** simple topology is active
- **AND** `resolve_container "BACKBONE"` is called
- **THEN** it returns `"clab-iran-filtering-iran-backbone"`

#### Scenario: Resolve backbone in realistic topology
- **WHEN** realistic topology is active
- **AND** `resolve_container "BACKBONE"` is called
- **THEN** it returns `"clab-iran-realistic-tic-tehran"`

#### Scenario: Resolve all roles in realistic topology
- **WHEN** realistic topology is active
- **THEN** `resolve_container "ISP"` returns `"clab-iran-realistic-isp-shatel"`
- **AND** `resolve_container "IXP"` returns `"clab-iran-realistic-tehran-ix"`
- **AND** `resolve_container "CLIENT"` returns `"clab-iran-realistic-client-tehran"`
- **AND** `resolve_container "INTERNET_SRV"` returns `"clab-iran-realistic-internet-srv"`
- **AND** `resolve_container "INTRANET"` returns `"clab-iran-realistic-iran-nin"`

### Requirement: Role-based interface resolution
`scripts/common.sh` SHALL provide a `resolve_interface(role, direction)` function that returns the correct network interface name for a given role and direction. The `direction` parameter SHALL be one of: `"internal"` (toward downstream/clients), `"external"` (toward upstream/internet), or a specific named direction as needed.

#### Scenario: Backbone internal interface in simple topology
- **WHEN** simple topology is active
- **AND** `resolve_interface "BACKBONE" "internal"` is called
- **THEN** it returns `"eth1"` (toward IXP)

#### Scenario: Backbone internal interface in realistic topology
- **WHEN** realistic topology is active
- **AND** `resolve_interface "BACKBONE" "internal"` is called
- **THEN** it returns the interface name on `tic-tehran` that faces the internal network

#### Scenario: ISP client-facing interface
- **WHEN** any topology is active
- **AND** `resolve_interface "ISP" "client"` is called
- **THEN** it returns the interface on the ISP node that faces the client node

### Requirement: Role-based IP resolution
`scripts/common.sh` SHALL provide a `resolve_ip(role, context)` function that returns IP addresses used in filtering rules and tests. The `context` parameter identifies which IP is needed (e.g., `"self"` for the node's primary IP, `"client_subnet"` for the client-facing subnet).

#### Scenario: ISP self IP in simple topology
- **WHEN** simple topology is active
- **AND** `resolve_ip "ISP" "self"` is called
- **THEN** it returns `"10.0.1.1"`

#### Scenario: ISP self IP in realistic topology
- **WHEN** realistic topology is active
- **AND** `resolve_ip "ISP" "self"` is called
- **THEN** it returns the ISP node's client-facing IP address in the realistic topology

#### Scenario: Internet server IP is consistent
- **WHEN** either topology is active
- **AND** `resolve_ip "INTERNET_SRV" "self"` is called
- **THEN** it returns `"203.0.113.2"` (same in both topologies)

### Requirement: Backward-compatible defaults
If topology detection fails or `common.sh` is sourced outside of a deployed environment, all resolution functions SHALL fall back to simple topology values. This ensures existing scripts do not break if run without changes in environments where only the simple topology exists.

#### Scenario: Fallback to simple topology
- **WHEN** no topology containers are detected
- **AND** `resolve_container "BACKBONE"` is called
- **THEN** it returns the simple topology default `"clab-iran-filtering-iran-backbone"`
- **AND** a warning is printed to stderr

### Requirement: Clab prefix variable
`scripts/common.sh` SHALL export a `CLAB_PREFIX` variable containing the containerlab prefix for the active topology (`"clab-iran-filtering"` for simple, `"clab-iran-realistic"` for realistic). This is used by `test.sh` and any script that constructs container names dynamically.

#### Scenario: Prefix for simple topology
- **WHEN** simple topology is active
- **THEN** `CLAB_PREFIX` equals `"clab-iran-filtering"`

#### Scenario: Prefix for realistic topology
- **WHEN** realistic topology is active
- **THEN** `CLAB_PREFIX` equals `"clab-iran-realistic"`
