# SSL materials (local only)

TLS certificates for optional tools reverse proxy are generated on the host and
must never be committed.

Generate locally (example):

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout tools.key -out tools.crt -days 825 \
  -subj "/CN=victron-tools.local"
chmod 600 tools.key
```

Ignored by git: `ssl/*.key`, `ssl/*.crt` (see `.gitignore`).
If a key was ever committed, rotate it and follow `SECURITY_REMOVE_SECRETS.md`.
