# Next steps — victron-ble2mqtt-integration

## Done in 2026-07 repo cleanup

- Untracked TLS key/cert (`ssl/tools.*`); see `SECURITY_REMOVE_SECRETS.md` for history purge.
- Pinned Home Assistant image (Phase 7.5); CI lints `override/` + package; retired soft-fail `ci-lint.yml`.
- Added `dotenv.sample`; corrected bootstrap path (alfa-ai) and clone URL; refreshed inventory / AI how-to stub.

## Recommended next (in order)

1. **History purge + rotate** — if `ssl/tools.key` was ever pushed, run `git filter-repo` (see `SECURITY_REMOVE_SECRETS.md`) and issue a new cert on the Pi.
2. **Hub reseed HA pin** — on `.111`, pull `ghcr.io/home-assistant/home-assistant:2026.7.3` and publish `home-assistant-2026.7.3.tar.gz`.
3. **Unify package tree** — collapse `override/victron_ble2mqtt` into `victron_ble2mqtt/` (or the reverse) so there is one runtime source.
4. **Phase 5 threat model** — short LAN threat paragraph in `DEPLOY.md` (Dockge `:5006`, MQTT plaintext, Watchtower socket).
5. **Optional audit pass** — research/audit under `docs/audit/` using the alfa-ai pattern (still valid; not blocking).

## Canonical docs

| Doc | Use |
|-----|-----|
| `DEPLOY.md` | Install / redeploy |
| `docs/ENGINEERING_STANDARDS_PLAN.md` | Standards roadmap |
| `REPO_INVENTORY.md` | Layout map |
