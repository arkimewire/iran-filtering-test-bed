# realistic-topology-transit-peering-cgnat

Improves the architectural realism of `topology-realistic.clab.yml` in three areas:

1. **Transit vs peering structural separation** — international traffic routes via TIC transit plane; domestic/NIN traffic routes via IX peering plane, surviving international shutdowns independently.

2. **Mobile CGNAT** — mobile operator nodes (`mob-*`) apply carrier-grade NAT, blocking unsolicited inbound connections and masking subscriber IPs, matching real-world mobile network behavior that affects VPN protocol behavior.

3. **East-west routing realism** — regional domestic traffic avoids mandatory north-south hairpin via the central Tehran node for NIN/domestic access.

BGP/FRR integration is explicitly deferred to a future phase.

## Files

| File | Purpose |
|------|---------|
| `proposal.md` | Why and what changes |
| `design.md` | Decisions, tradeoffs, rollout plan |
| `tasks.md` | Actionable implementation checklist |
| `specs/realistic-topology/spec.md` | Formal behavior specifications |
