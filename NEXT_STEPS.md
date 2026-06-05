# Next Steps — victron-ble2mqtt-integration

## Next step (planned): research + audit subagent pass

Run the two-stage subagent workflow developed in `alfa-ai/docs/audit/` during the May 2026 ALFa AI architectural audit. The pattern surfaced 64 findings (17 Critical) on alfa-ai; we want the same coverage on every active repo before resuming feature work.

1. **Research Agent** — gathers OFFICIAL upstream docs for every technology this repo uses (Victron BLE protocol, MQTT broker version + auth, Home Assistant integration, Docker Swarm deployment, etc. — versions, security posture, best practices, deprecations). Writes per-component facts + an audit checklist to `docs/audit/research/<component>.md` and a master `docs/audit/research/INDEX.md`.
2. **Audit Agent** — reads the research files, audits this repo against the embedded checklists + cross-cutting checks (internal-doc consistency, stale references, security-currency vs published CVEs, cluster-rules compliance — port assignments, network names, deployment-process ownership, Docker build pattern). Writes findings + a severity-ranked remediation backlog to `docs/audit/audit-findings.md`.

Both passes are read-only on the host stack — they only write into the new `docs/audit/` directory. Remediation is gated on explicit per-finding approval.

**Reference workflow:**
- Pattern: `/home/ansible/alfa-ai/docs/audit/`
- Research output format: `/home/ansible/alfa-ai/docs/audit/research/INDEX.md`
- Audit output format: `/home/ansible/alfa-ai/docs/audit/audit-findings.md`

Added 2026-05-13 after the alfa-ai audit proved the pattern at scale.
