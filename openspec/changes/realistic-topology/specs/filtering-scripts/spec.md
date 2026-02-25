## MODIFIED Requirements

### Requirement: Filtering scripts use topology-aware container and interface resolution
All 20 filtering scripts in `scripts/` SHALL replace their hardcoded `CONTAINER_NAME` and `INTERFACE` variables with calls to `common.sh` resolution functions. Each script SHALL source `common.sh` and use `resolve_container`, `resolve_interface`, and `resolve_ip` to determine targets at runtime. The filtering logic (nftables rules, iptables rules, tc qdisc, Python proxy) SHALL remain identical.

#### Scenario: Backbone filtering script on simple topology
- **WHEN** simple topology is active
- **AND** user runs `./scripts/3.1-ip-blocking.sh on`
- **THEN** the script applies nftables rules to `clab-iran-filtering-tic-tehran`
- **AND** behavior is identical to the current hardcoded implementation

#### Scenario: Backbone filtering script on realistic topology
- **WHEN** realistic topology is active
- **AND** user runs `./scripts/3.1-ip-blocking.sh on`
- **THEN** the script applies nftables rules to `clab-iran-realistic-tic-tehran`
- **AND** the same nftables table/chain/rule logic is used

#### Scenario: ISP filtering script on simple topology
- **WHEN** simple topology is active
- **AND** user runs `./scripts/1.1-dns-hijacking.sh on`
- **THEN** the script applies rules to `clab-iran-filtering-isp-shatel` on interface `eth1`

#### Scenario: ISP filtering script on realistic topology
- **WHEN** realistic topology is active
- **AND** user runs `./scripts/1.1-dns-hijacking.sh on`
- **THEN** the script applies rules to the resolved ISP container on its client-facing interface

#### Scenario: Kill switch script on simple topology
- **WHEN** simple topology is active
- **AND** user runs `./scripts/7.1-kill-switch.sh on`
- **THEN** the script applies nftables drop rules to `clab-iran-filtering-tehran-ix` on interface `eth1`

#### Scenario: Kill switch script on realistic topology
- **WHEN** realistic topology is active
- **AND** user runs `./scripts/7.1-kill-switch.sh on`
- **THEN** the script applies nftables drop rules to the resolved IXP (or backbone) container on the appropriate interface
- **AND** the effect is that `client-tehran` cannot reach `internet-srv`

#### Scenario: tc-based scripts use correct interface
- **WHEN** any topology is active
- **AND** user runs `./scripts/6.4-selective-bandwidth-throttling.sh on`
- **THEN** the TBF qdisc is applied to the resolved BACKBONE container on the resolved internal interface

#### Scenario: Script on/off/status cycle unchanged
- **WHEN** any filtering script is toggled on, checked status, then toggled off
- **THEN** the on/off/status behavior is identical to the current implementation
- **AND** status correctly reports ON or OFF

#### Scenario: Scripts share config files across topologies
- **WHEN** any filtering script reads from `config/backbone/*.conf` or `config/isp/*.conf`
- **THEN** the same config files are used regardless of which topology is active

### Requirement: common.sh preserves existing functionality
The existing `PRIV_MARK`, `is_tiered_access_active()`, and `nft_insert_priv_exemption()` functions in `common.sh` SHALL continue to work correctly. The `is_tiered_access_active()` function SHALL accept an optional container parameter and default to the resolved BACKBONE container (currently defaults to `clab-iran-filtering-tic-tehran`).

#### Scenario: Tiered access check on simple topology
- **WHEN** simple topology is active
- **AND** `is_tiered_access_active` is called without arguments
- **THEN** it checks `clab-iran-filtering-tic-tehran` for the `global_whitelist` table

#### Scenario: Tiered access check on realistic topology
- **WHEN** realistic topology is active
- **AND** `is_tiered_access_active` is called without arguments
- **THEN** it checks `clab-iran-realistic-tic-tehran` for the `global_whitelist` table

### Requirement: All 20 scripts remain individually executable
Each script SHALL remain a standalone executable that can be invoked as `./scripts/X.Y-name.sh {on|off|status}`. No wrapper script or additional arguments SHALL be required. Topology detection SHALL be automatic.

#### Scenario: Direct script execution
- **WHEN** user runs `./scripts/4.1-sni-filtering.sh on`
- **THEN** the script auto-detects the active topology, resolves the target container, and applies the filtering rules
- **AND** no additional arguments or environment variables are required
