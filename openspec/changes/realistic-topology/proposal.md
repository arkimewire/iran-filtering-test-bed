## Why

The existing `topology.clab.yml` uses a simplified 6-node linear chain (`internet -> backbone -> ixp -> isp -> client + intranet`) which is excellent for quickly testing filtering scripts but does not reflect Iran's actual internet architecture. Cross-referencing 15+ independent sources -- BGP registries (bgp.he.net, bgp.tools), PeeringDB, FilterWatch investigative reports (Jan-Feb 2026), Whisper Security forensic analysis, academic papers (IRBlock USENIX 2025, Paderborn University), IODA/Kentik/Cloudflare monitoring data, and Internet Society IXP Tracker -- reveals several structural inaccuracies in the simple topology that matter for realistic simulation:

1. **Kill switch location is wrong**: The simple topology's kill switch operates at the IXP layer (cutting IXP-ISP links). In reality, the January 2026 shutdown was executed via BGP route withdrawal at TIC's international gateways -- a control-plane operation, not a data-plane link cut.
2. **International connectivity is not a single link**: Iran connects to the global internet through at least two distinct physical paths -- the FALCON submarine cable (landing at Bandar Abbas) and the EPEG terrestrial cable (entering via Azerbaijan/Turkey border) -- both controlled by TIC (AS49666/48159).
3. **No geographic/regional dimension**: The simple topology cannot simulate regional shutdowns (e.g., cutting Isfahan while Tehran stays up), which FilterWatch documented extensively during Dec 2025 - Jan 2026 protests.
4. **ISP diversity missing**: Iran's ISP landscape has structurally different players -- fixed-line wholesale (TCI AS58224), mobile operators (MCI AS197207, IranCell AS44244), and retail ISPs (Shatel) -- each with different filtering enforcement behaviors confirmed across ISPs by Kentik traffic data.
5. **Tehran IX overstated**: The simple topology gives Tehran IX a central routing role. In reality, Tehran IX has only 3 members (PeeringDB) and serves primarily as a domestic traffic control point, not a robust peering fabric.

A second, more realistic topology file enables testing scenarios the simple topology cannot: multi-path international connectivity, regional shutdowns, ISP-specific filtering behavior, realistic kill switch mechanics, and the domestic/international traffic split that defines the NIN (National Information Network).

## What Changes

- **New file**: `topology-realistic.clab.yml` -- a ~15-node containerlab topology modeling Iran's actual internet hierarchy (no mobile node)
- **No changes** to the existing `topology.clab.yml` (kept as the "simple/lightweight" topology)
- **New config directory**: `config-realistic/` for topology-specific configuration files (DNS, nftables, etc.)
- **Refactored filtering scripts**: All 20 scripts in `scripts/` must work with BOTH topologies. Currently each script hardcodes a `CONTAINER_NAME` (e.g., `clab-iran-filtering-iran-backbone`) and `INTERFACE` (e.g., `eth1`). These must be made topology-aware via `scripts/common.sh`.
- **Refactored test.sh**: Must detect which topology is active and run the full test suite against either one. Currently hardcodes `C="clab-iran-filtering"` and uses hardcoded container names / IPs throughout.

### Node inventory (~15 nodes):

| Layer | Node | Real-world entity | AS / Role |
|-------|------|--------------------|-----------|
| International | `internet-srv` | Global internet / DE-CIX peering | External |
| Border Gateway | `gw-falcon` | FALCON submarine cable landing | TIC border router (Bandar Abbas) |
| Border Gateway | `gw-epeg` | EPEG terrestrial cable entry | TIC border router (Azerbaijan/Turkey border) |
| TIC Core | `tic-tehran` | TIC Tehran headquarters | AS49666 -- main DPI/filtering hub, BGP kill switch |
| TIC Regional | `tic-south` | TIC southern backbone | Isfahan, Shiraz, Bushehr coverage |
| TIC Regional | `tic-east` | TIC eastern backbone | Mashhad, Tabriz coverage |
| IXP | `tehran-ix` | Tehran IX | Domestic traffic exchange (3 members) |
| Tier-2 | `tci` | Telecommunication Company of Iran | AS58224 -- largest fixed-line wholesale |
| ISP | `isp-shatel` | Shatel | Major retail fixed ISP |
| Mobile | `mob-mci` | MCI / Hamrah Aval | AS197207 -- largest mobile operator |
| Mobile | `mob-irancell` | IranCell | AS44244 -- second mobile operator |
| End User | `client-tehran` | Tehran end user | Fixed-line + mobile access |
| End User | `client-mobile` | Mobile end user (Android subscriber) | Represents non-Tehran mobile users |
| Domestic | `aparat-server` | NIN domestic services | ArvanCloud CDN, banking, Eitaa, Rubika |
| Academic | `ipm-academic` | IPM / Fundamental Sciences Institute | AS6736 -- academic gateway (minor) |

### Key architectural corrections vs simple topology:

1. **Kill switch at TIC level**: `tic-tehran` controls BGP route announcements to `gw-falcon`/`gw-epeg`. Kill switch = route withdrawal, not link cut.
2. **Dual international paths**: Two distinct border gateways (FALCON + EPEG) both connecting through `tic-tehran`.
3. **Regional backbone**: `tic-south` and `tic-east` enable simulation of regional shutdowns (cutting one region while others stay up).
4. **ISP diversity**: Separate fixed (Shatel), mobile (MCI, IranCell), and wholesale (TCI) nodes with independent filtering capability.
5. **Correct IXP role**: `tehran-ix` primarily for domestic traffic exchange (connecting to `aparat-server`), not as a routing chokepoint.
6. **Academic gateway**: IPM (AS6736) has separate privileged access, consistent with Jan 2026 whitelisting data (universities whitelisted first on Jan 9).
7. **IRGC control layer**: `tic-tehran` represents the "militarized" TIC where IRGC Cyber HQ (per FilterWatch Feb 2026) has command authority.
8. **Geolocation filtering**: Implementable at `tic-tehran` as CIDR blocking of Israel IP ranges (per user's network engineer source).

## Capabilities

### New Capabilities

- `realistic-topology`: The containerlab topology file (`topology-realistic.clab.yml`) with ~15 nodes (no mobile node), IP addressing scheme, link definitions, and per-node exec initialization. Includes the physical topology, routing configuration, and NAT/masquerade for real internet access via backbone.
- `realistic-topology-configs`: Per-node configuration files (`config-realistic/`) for DNS (dnsmasq), nftables base rules, and routing tables that make the topology functional.
- `topology-abstraction`: An abstraction layer in `scripts/common.sh` that maps abstract roles (BACKBONE, ISP, IXP, CLIENT, INTERNET_SRV, INTRANET) to concrete container names and interface names for the active topology. Auto-detects which topology is running.

### Modified Capabilities

- `filtering-scripts`: All 20 scripts refactored to use `common.sh` role-based container/interface resolution instead of hardcoded `CONTAINER_NAME` and `INTERFACE` values. The role-to-node mapping for each topology:

  | Role | Simple topology node | Realistic topology node |
  |------|---------------------|------------------------|
  | BACKBONE | `iran-backbone` | `tic-tehran` |
  | ISP | `iran-isp` | `isp-shatel` |
  | IXP | `iran-ixp` | `tehran-ix` |
  | CLIENT | `iran-client` | `client-tehran` |
  | INTERNET_SRV | `internet-srv` | `internet-srv` |
  | INTRANET | `iran-intranet` | `aparat-server` |

- `test-suite`: `test.sh` refactored to detect active topology and resolve container names, IPs, and interfaces dynamically. All 26 test sections must pass on both topologies.

## Impact

- **New files**: `topology-realistic.clab.yml`, `config-realistic/` directory tree.
- **Modified files**: `scripts/common.sh` (add topology detection + role mapping), all 20 `scripts/*.sh` (replace hardcoded CONTAINER_NAME/INTERFACE), `test.sh` (parameterize container prefix, node names, IPs).
- **Resource usage**: ~15 containers vs ~6 for simple topology. Requires more RAM/CPU but well within typical containerlab deployments.
- **Containerlab namespace**: Uses name `iran-realistic` (separate from `iran-filtering`) so both topologies can be deployed independently.
- **Backward compatibility**: Existing simple topology behavior is preserved exactly. Scripts default to simple topology if detection fails.
- **No mobile node** in the realistic topology (may be added later).

### Script abstraction design

Currently every script has:
```bash
CONTAINER_NAME="clab-iran-filtering-iran-backbone"
INTERFACE="eth1"
```

After refactoring, `common.sh` will provide:
```bash
# Auto-detect which topology is running
detect_topology()  # returns "simple" or "realistic"

# Role-based resolution
resolve_container "BACKBONE"  # returns full container name
resolve_interface "BACKBONE" "internal"  # returns interface name
```

Each script will replace its hardcoded values with:
```bash
source "$(dirname "$0")/common.sh"
CONTAINER_NAME=$(resolve_container "BACKBONE")
INTERFACE=$(resolve_interface "BACKBONE" "internal")
```

Detection works by checking which clab containers exist:
- If `clab-iran-filtering-iran-backbone` exists -> simple topology
- If `clab-iran-realistic-tic-tehran` exists -> realistic topology

### Sources cross-referenced for this proposal

1. FilterWatch: "Exclusive Report: The Network Behind Iran's Internet Shutdown" (Feb 2026) -- named TIC CEO, IRGC Cyber HQ commander, Tehran IX architect, Doran Group team
2. FilterWatch: "Total Blackout: A Technical Breakdown of the January 2026 Shutdown" (Jan 2026) -- IPv6 route withdrawal, whitelisting progression
3. FilterWatch: "From Regional Disruptions to Nationwide Blackouts" (Jan 2026) -- regional shutdown mechanics, per-operator Kentik data
4. FilterWatch: "A Month of Iran's Internet: Whitelisted Reality" (Jan 2026) -- whitelist model, 25% traffic restoration
5. FilterWatch: "Stealth Blackout: June 2025 Shutdown" (Oct 2025) -- protocol whitelisting, DPI evolution
6. FilterWatch: "Internet Infrastructure Monopoly" (Sep 2024) -- TIC monopoly, IXP control, filtering distribution
7. FilterWatch: "Tiered Internet" (Jul 2025) -- NIN tiered access model
8. FilterWatch: "Digital Repression in Bandar Abbas" (Apr 2025) -- southern regional disruption
9. PeeringDB: Tehran IX records (3 members), TIC peering records (DE-CIX Frankfurt 200G, Istanbul 100G, NL-ix 200G)
10. bgp.he.net / bgp.tools: AS49666 (TIC), AS58224 (TCI), AS12880 (ITC), AS197207 (MCI), AS44244 (IranCell), AS6736 (IPM)
11. Wikipedia: FALCON submarine cable (Bandar Abbas landing), EPEG terrestrial cable (Azerbaijan route)
12. Whisper Security: "Anatomy of Iran's Internet" (Jan 2026) -- forensic BGP analysis of shutdown
13. IRBlock (USENIX Security 2025) -- measurement of DNS poisoning, HTTP blockpage injection
14. Reza Harirchian (Medium) -- layered control stack framework (routing > transport > application)
15. User's network engineer contact -- IRGC gateway control, ISP vs ISDP distinction, geolocation filtering
16. Doug Madory / Kentik: "From Stealth Blackout to Whitelisting" (Jan 2026) -- TIC disconnected from Rostelecom (AS12389) and GBI (AS200612); IPv4 routes kept while traffic blocked; diurnal whitelisting pattern on AS49666
17. datanarrative.online: "Understanding Iran's Internet Blackout" (Jan 2026) -- upstream transit diagram (Telecom Italia AS6762, GTT AS3257, Orange AS5511); stealth outage explanation
18. Ryan Bagley: "Anatomy of Iran's Internet" (Jan 2026) -- Top 10 Iranian AS by cone size; AS12880 (ITC) cone=261 under AS49666; NIN architecture diagram from Hesam Norouz Pour (EUI)
19. Collin Anderson: "The Hidden Internet of Iran" (arXiv 2012) -- NIN uses RFC1918 (10.x.x.x) address space; original mapping of domestic intranet
20. Citizen Lab: "Iran's National Information Network" (2012) -- NIN three-phase design; domestic/international bifurcation
21. ASCII News: "Iran Internet Shutdown BGP Withdrawal Data Analysis" (Jan 2026) -- IPv6 space dropped 98.5%; HTTP/3 protocol filtering preceded shutdown by 9 days
