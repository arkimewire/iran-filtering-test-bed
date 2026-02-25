## ADDED Requirements

### Requirement: Per-node DNS configuration
The topology SHALL provide dnsmasq configuration files for ISP-layer nodes (`isp-shatel`, `mob-mci`, `mob-irancell`) that serve as local DNS resolvers for their downstream clients. The DNS blocklist SHALL reuse the same blocked domains as the simple topology (`config/isp/blocklist.conf`). The backbone node (`tic-tehran`) SHALL also run dnsmasq for upstream DNS forwarding.

#### Scenario: ISP DNS resolver is functional
- **WHEN** the topology is deployed
- **THEN** `isp-shatel` runs dnsmasq and responds to DNS queries from `client-tehran`
- **AND** unblocked domains resolve correctly

#### Scenario: DNS blocklist is shared with simple topology
- **WHEN** a domain is listed in `config/isp/blocklist.conf`
- **THEN** the same domain is blocked in both simple and realistic topology ISP DNS resolvers

### Requirement: Per-node nftables base configuration
Each forwarding node (`tic-tehran`, `tic-south`, `tic-east`, `gw-falcon`, `gw-epeg`, `tehran-ix`, `tci`, `isp-shatel`, `mob-mci`, `mob-irancell`) SHALL load a base nftables configuration on startup that enables IP forwarding and applies NAT/masquerade where needed. These configs SHALL be stored in `config-realistic/`.

#### Scenario: IP forwarding enabled on all forwarding nodes
- **WHEN** the topology is deployed
- **THEN** every forwarding node has `net.ipv4.ip_forward=1`

#### Scenario: NAT/masquerade on backbone
- **WHEN** `tic-tehran` forwards traffic to `internet-srv`
- **THEN** source NAT is applied so return traffic routes correctly

### Requirement: Config directory structure
Configuration files for the realistic topology SHALL be stored under `config-realistic/` with subdirectories per node role. Shared config files (e.g., `config/backbone/sni_blocklist.conf`, `config/backbone/blocklist.conf`) SHALL be reused from the existing `config/` directory where the filtering logic is identical.

#### Scenario: Shared blocklists
- **WHEN** a filtering script reads `config/backbone/sni_blocklist.conf`
- **THEN** the same file is used regardless of which topology is active
- **AND** no duplicate blocklist files exist in `config-realistic/`

#### Scenario: Topology-specific DNS configs
- **WHEN** the realistic topology is deployed
- **THEN** ISP nodes bind-mount their dnsmasq configs from `config-realistic/isp-shatel/` (or similar)
- **AND** backbone node bind-mounts from `config-realistic/tic-tehran/`
