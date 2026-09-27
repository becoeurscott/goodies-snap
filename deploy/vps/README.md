# AI gateway (VPS)

Exposes the Ollama on the Hostinger VPS (`srv1322523`, `157.173.210.2`) to app backends at
`https://ai.goodiessnap.com`.

```
app backend (InsForge function) --HTTPS + app key--> Caddy :443 --> Ollama 127.0.0.1:11434
```

- Ollama never listens publicly; Caddy is the only public listener.
- Every request needs `Authorization: Bearer <app key>`; one key per app, stored in
  `/etc/caddy/app-keys/<app>` (root only). Wrong or missing key → `401`.
- Only inference endpoints are forwarded (`/api/chat`, `/api/embed`, `/v1/chat/completions`, …).
  Model management (`/api/pull`, `/api/delete`, …) → `404`.
- Keys are stripped from the access log (`/var/log/caddy/ai-access.log`).
- Models: `qwen2.5:3b` for chat, `nomic-embed-text` for knowledge search. Ollama keeps them
  loaded permanently and serves 2 chats in parallel (2 vCPU, no GPU).

## Run

As root on the VPS:

```bash
bash setup-ai-gateway.sh                  # first install / refresh
bash setup-ai-gateway.sh --add-app NAME   # key for another app
bash setup-ai-gateway.sh --rotate NAME    # replace an app's key
```

It prints each app's key at the end. Put the goodiessnap key in InsForge as the
`OLLAMA_API_KEY` secret, with `OLLAMA_URL=https://ai.goodiessnap.com`. Never commit a key.

## Firewall (Hostinger)

Allow inbound TCP 22 (SSH), 80 (certificate renewal) and 443 (HTTPS) only.

## FreeLLMAPI (free-tier LLM router)

`setup-freellmapi.sh` runs [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi) at
`https://srv1322523.hstgr.cloud`: one OpenAI-compatible API over the free tiers of many
providers, plus this VPS's Ollama (`qwen2.5:3b`).

- Docker container on the host network, listening on `127.0.0.1:3001` only; Caddy publishes it
  with HTTPS from `/etc/caddy/sites/freellmapi.caddy`.
- The dashboard account is created from config before first start (no open setup page); the
  generated password is printed once and kept in `/opt/freellmapi/admin-password` (root only).
- Data (encrypted provider keys, usage) lives in the `freellmapi-data` Docker volume;
  `/opt/freellmapi/.env` holds `ENCRYPTION_KEY` — back it up, it can't be recovered.
- Update: `cd /opt/freellmapi && docker compose pull && docker compose up -d`.
