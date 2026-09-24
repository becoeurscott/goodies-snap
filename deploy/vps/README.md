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
  loaded for 24h and serves 2 chats in parallel (2 vCPU, no GPU).

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
