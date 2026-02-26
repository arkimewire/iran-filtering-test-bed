## MODIFIED Requirements

### Requirement: test.sh detects and tests against active topology
`test.sh` SHALL auto-detect which topology is deployed and run the full test suite against it. It SHALL source `scripts/common.sh` and use the topology abstraction layer to resolve container names, interface names, and IP addresses.

#### Scenario: Tests pass on simple topology
- **WHEN** simple topology is deployed
- **AND** user runs `./test.sh`
- **THEN** all 26 test sections execute against `clab-iran-filtering-*` containers
- **AND** all tests pass (identical to current behavior)

#### Scenario: Tests pass on realistic topology
- **WHEN** realistic topology is deployed
- **AND** user runs `./test.sh`
- **THEN** all 26 test sections execute against `clab-iran-realistic-*` containers
- **AND** all tests pass

#### Scenario: Test reports which topology is being tested
- **WHEN** `test.sh` starts execution
- **THEN** it prints which topology was detected (e.g., `"Detected topology: simple"` or `"Detected topology: realistic"`)

### Requirement: test.sh uses parameterized container references
`test.sh` SHALL NOT contain hardcoded container name prefixes or node-specific names. The current `C="clab-iran-filtering"` and all `run iran-client "..."` patterns SHALL use resolved values from `common.sh`.

#### Scenario: Container prefix is dynamic
- **WHEN** realistic topology is active
- **AND** test.sh calls `run` helper with role `CLIENT`
- **THEN** the command executes in `clab-iran-realistic-client-tehran`

#### Scenario: Container prefix is dynamic for simple topology
- **WHEN** simple topology is active
- **AND** test.sh calls `run` helper with role `CLIENT`
- **THEN** the command executes in `clab-iran-filtering-iran-client`

### Requirement: test.sh uses parameterized IP addresses
All IP addresses used in test assertions SHALL be resolved from the topology abstraction or defined as variables at the top of the script. The same test logic SHALL work with potentially different IP schemes across topologies.

#### Scenario: Internet server IP in assertions
- **WHEN** test.sh asserts connectivity to the internet server
- **THEN** it uses the resolved IP for `INTERNET_SRV` (currently `203.0.113.2` in both topologies)

#### Scenario: Client-to-ISP ping uses resolved IPs
- **WHEN** test.sh tests layer 3 connectivity (section 2)
- **THEN** it pings the resolved ISP IP, not a hardcoded `10.0.1.1`

### Requirement: test.sh container health checks cover topology nodes
Section 1 (container health) SHALL check all nodes present in the active topology. For the simple topology this is 6 nodes; for the realistic topology this is ~15 nodes.

#### Scenario: Health check for simple topology
- **WHEN** simple topology is active
- **THEN** section 1 checks 6 nodes: `iran-client`, `isp-shatel`, `tehran-ix`, `tic-tehran`, `internet-srv`, `aparat-server`

#### Scenario: Health check for realistic topology
- **WHEN** realistic topology is active
- **THEN** section 1 checks all ~15 nodes including `tic-tehran`, `gw-falcon`, `gw-epeg`, `tic-south`, `tic-east`, `tehran-ix`, `tci`, `isp-shatel`, `mob-mci`, `mob-irancell`, `client-tehran`, `client-mobile`, `internet-srv`, `aparat-server`, `ipm-academic`

### Requirement: test.sh filtering tests use script abstraction
Filtering mechanism tests (sections 5-25) SHALL invoke the same `./scripts/*.sh` scripts and verify behavior through the topology abstraction. The scripts themselves handle topology detection; test.sh only needs to verify outcomes from the correct client/server containers.

#### Scenario: DNS hijacking test on realistic topology
- **WHEN** realistic topology is active
- **AND** test section 5 runs `./scripts/1.1-dns-hijacking.sh on`
- **THEN** the test verifies DNS resolution from `client-tehran` returns the censorship IP for blocked domains

#### Scenario: Kill switch test on realistic topology
- **WHEN** realistic topology is active
- **AND** test section 22 runs `./scripts/7.1-kill-switch.sh on`
- **THEN** `client-tehran` cannot reach `internet-srv`
- **AND** `client-tehran` cannot reach real internet (`1.1.1.1`)

### Requirement: test.sh idempotency and integration tests
Sections 25 (tiered access + protocol whitelisting integration) and 26 (idempotency) SHALL work identically on both topologies, verifying that multi-script interactions and double on/off cycles behave correctly.

#### Scenario: Tiered access integration on realistic topology
- **WHEN** realistic topology is active
- **AND** 7.2 and 7.3 are both enabled
- **THEN** mark-based exemptions are correctly injected into protocol whitelisting chains on the resolved BACKBONE container

#### Scenario: Idempotency on realistic topology
- **WHEN** realistic topology is active
- **AND** a script is enabled twice and disabled twice
- **THEN** no duplicate rules are created and the filter is fully removed
