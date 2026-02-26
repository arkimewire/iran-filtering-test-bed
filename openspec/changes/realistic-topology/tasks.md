## 1. Topology Abstraction Layer (Phase 1 -- no new topology yet)

- [x] 1.1 Update `scripts/common.sh`: add `detect_topology()` function that checks for sentinel containers and returns `"simple"` or `"realistic"`, with `IRAN_TOPOLOGY` env var override
- [x] 1.2 Update `scripts/common.sh`: add `resolve_container(role)` function with role-to-container mapping for both topologies (BACKBONE, ISP, IXP, CLIENT, INTERNET_SRV, INTRANET)
- [x] 1.3 Update `scripts/common.sh`: add `resolve_interface(role, direction)` function with interface mapping for both topologies
- [x] 1.4 Update `scripts/common.sh`: add `resolve_ip(role, context)` function for topology-aware IP resolution
- [x] 1.5 Update `scripts/common.sh`: export `CLAB_PREFIX` variable based on detected topology
- [x] 1.6 Update `scripts/common.sh`: update `is_tiered_access_active()` default container to use `resolve_container "BACKBONE"` instead of hardcoded value

## 2. Refactor Filtering Scripts (Phase 1)

- [x] 2.1 Refactor `scripts/1.1-dns-hijacking.sh`: replace hardcoded `CONTAINER_NAME` and `INTERFACE` with `resolve_container "ISP"` and `resolve_interface "ISP" "client"`
- [x] 2.2 Refactor `scripts/1.2-doh-dot-blocking.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.3 Refactor `scripts/2.1-http-host-filtering.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.4 Refactor `scripts/3.1-ip-blocking.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.5 Refactor `scripts/3.2-bgp-hijacking.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.6 Refactor `scripts/3.3-ipv6-filtering.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.7 Refactor `scripts/4.1-sni-filtering.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.8 Refactor `scripts/4.2-tls-fingerprinting.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.9 Refactor `scripts/4.3-tcp-rst-injection.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.10 Refactor `scripts/5.1-encapsulated-protocol-detection.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.11 Refactor `scripts/5.2-packet-manipulation.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.12 Refactor `scripts/5.3-active-probing.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.13 Refactor `scripts/6.1-behavioral-pattern-recognition.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.14 Refactor `scripts/6.2-protocol-specific-throttling.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.15 Refactor `scripts/6.3-dynamic-ip-reputation.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.16 Refactor `scripts/6.4-selective-bandwidth-throttling.sh`: replace hardcoded values with `resolve_container "BACKBONE"` and `resolve_interface "BACKBONE" "internal"`
- [x] 2.17 Refactor `scripts/6.5-degradation-based-filtering.sh`: replace hardcoded values with `resolve_container "BACKBONE"` and `resolve_interface "BACKBONE" "internal"`
- [x] 2.18 Refactor `scripts/7.1-kill-switch.sh`: add topology-aware logic -- IXP in simple, BACKBONE in realistic, with correct interface per topology
- [x] 2.19 Refactor `scripts/7.2-tiered-access.sh`: replace hardcoded values with `resolve_container "BACKBONE"`
- [x] 2.20 Refactor `scripts/7.3-protocol-whitelisting.sh`: replace hardcoded values with `resolve_container "BACKBONE"`

## 3. Refactor test.sh (Phase 1)

- [x] 3.1 Update `test.sh`: source `scripts/common.sh` and replace `C="clab-iran-filtering"` with `CLAB_PREFIX` from common.sh
- [x] 3.2 Update `test.sh`: replace `run()` helper to use resolved container names (role-based `run_role()` and node-based `run_node()`)
- [x] 3.3 Update `test.sh`: parameterize section 1 (container health) to check topology-appropriate node list
- [x] 3.4 Update `test.sh`: parameterize section 2 (network connectivity) IP addresses using `resolve_ip`
- [x] 3.5 Update `test.sh`: parameterize all filtering test sections (5-25) to use resolved container names for `docker exec` assertions
- [x] 3.6 Update `test.sh`: add topology detection banner at startup (print which topology detected)
- [x] 3.7 Verify: deploy simple topology, run `test.sh`, confirm all tests still pass identically

## 4. Create Realistic Topology File (Phase 2)

- [x] 4.1 Create `topology-realistic.clab.yml` with lab name `iran-realistic` and all ~15 nodes using `iran-sim:latest` image
- [x] 4.2 Define all links between nodes per the design document IP addressing scheme (15 links)
- [x] 4.3 Add `exec` blocks for each node: IP address assignment, static routes, sysctl ip_forward
- [x] 4.4 Add interface assignment comment block documenting ethN mapping per node
- [x] 4.5 Add NAT/masquerade on `tic-tehran` for real internet access via Docker bridge (eth0)

## 5. Create Realistic Topology Configs (Phase 2)

- [x] 5.1 Create `config-realistic/tic-tehran/dnsmasq.conf` for backbone DNS forwarding
- [x] 5.2 Create `config-realistic/tic-tehran/nftables.conf` for backbone base rules (NAT/masquerade)
- [x] 5.3 Create `config-realistic/isp-shatel/dnsmasq.conf` for ISP DNS (reusing `config/isp/blocklist.conf`)
- [x] 5.4 Create `config-realistic/isp-shatel/nftables.conf` for ISP base rules
- [x] 5.5 OBSOLETE: SR Linux configs replaced by Linux static routes in `topology-realistic.clab.yml`
- [x] 5.6 Add bind mounts in `topology-realistic.clab.yml` for config files on relevant linux nodes

## 6. Integration Testing (Phase 2)

- [x] 6.1 Build image: `./build.sh`
- [x] 6.2 OBSOLETE: SR Linux image pull no longer needed
- [x] 6.3 Deploy realistic topology: `clab deploy -t topology-realistic.clab.yml`
- [x] 6.4 Verify all nodes are running (all linux kind)
- [x] 6.5 Verify forwarding nodes have correct IP routing and NAT
- [x] 6.6 Verify end-to-end connectivity: `client-tehran` -> `internet-srv` and `client-tehran` -> `aparat-server`
- [x] 6.7 Verify `client-mobile` -> `internet-srv` via regional backbone path
- [x] 6.8 Verify real internet access: `client-tehran` can ping `1.1.1.1`
- [x] 6.9 Run `test.sh` against realistic topology -- all 26 sections must pass
- [x] 6.10 Destroy realistic topology, deploy simple topology, run `test.sh` -- confirm simple topology still passes
- [x] 6.11 Fix any test failures discovered in 6.9 or 6.10

## 7. Documentation

- [x] 7.1 Update AGENTS.md: document all-linux node strategy for performance and consistency.
