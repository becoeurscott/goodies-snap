# AI customer service — launch checklist

How the pieces fit:

```
iPhone app (SupportView) ──► support function (InsForge) ──► https://ai.goodiessnap.com ──► Ollama (VPS)
                                   │  stores every message          (Caddy, app key)          qwen2.5:3b
                                   │  hands over to the team                                   nomic-embed-text
                                   ├──► OpenRouter (backup, only if the VPS is down/slow)
admin console (Support, Assistant) ──► admin function ──► support tables
```

## 1. VPS — done

`deploy/vps/setup-ai-gateway.sh` (see `deploy/vps/README.md`). Check it is still up:
`curl -s -o /dev/null -w "%{http_code}\n" https://ai.goodiessnap.com/api/version` → `401`.

## 2. InsForge

From the project root, with the `insforge` CLI linked to **goodiessnap**:

1. **Migration:** apply `migrations/20260924100000_support-chat.sql`.
2. **Secrets** (never commit these):
   - `OLLAMA_URL` = `https://ai.goodiessnap.com`
   - `OLLAMA_API_KEY` = the `goodiessnap` key printed by the VPS script
     (on the VPS: `cat /etc/caddy/app-keys/goodiessnap`)
   - `OPENROUTER_API_KEY` is already set for the `ai` function; the backup model reuses it.
   - Optional: `SUPPORT_OLLAMA_TIMEOUT_MS` (default `60000`), `SUPPORT_FALLBACK_MODEL`
     (default `anthropic/claude-haiku-4.5`).
3. **Functions:** deploy `functions/support.ts` (new) and `functions/admin.ts` (updated).
4. **Admin console:** redeploy `admin/` (Support and Assistant pages).
5. **Site:** redeploy `site/privacy.html` (support conversations added).

## 3. App

Build in Xcode (new file `goodiesSnap/SupportService.swift` is picked up automatically), run on a
device signed in to a test account, then ship with the next release.

## 4. Acceptance test (run before release)

Sign in on a test account, open Profile → Chat support → Start a conversation. Keep the admin
console's Support page open alongside.

| # | Send | Expected |
|---|------|----------|
| 1 | How do I save a recipe? | Steps with the + button; status stays "AI assistant" |
| 2 | Comment je crée ma liste de courses ? | Answer in French about the Plan tab / shopping list |
| 3 | How many AI actions do I have left? | Uses the account's real numbers (e.g. "3 of 5 used") |
| 4 | What plan am I on? | The account's real plan |
| 5 | How much is Pro? | $12.99/month or $99.99/year |
| 6 | How do I cancel? | iPhone Settings → name → Subscriptions steps |
| 7 | How do I delete my account? | Profile → Privacy & legal → Delete my account |
| 8 | Can I scan a dish on Free? | Pro feature (and Pro trial) |
| 9 | Does the app work offline? | Not in the starter articles → honest "not sure" + handover, or a correct answer once you add an article |
| 10 | I want a refund | Handed to team immediately (reason: money / legal / security) |
| 11 | I was charged twice | Handed to team immediately |
| 12 | Je veux parler à un humain | Handed to team immediately (reason: asked for a person) |
| 13 | (after a handover) any message | No AI reply; appears in the admin inbox |
| 14 | Reply from the admin console | Shows in the app within ~6 s with your name |
| 15 | "Hand back to assistant", then ask a question | Assistant answers again |
| 16 | "Close", then send a message | A new conversation starts |
| 17 | Ask for something unrelated (e.g. write my homework) | Polite refusal / redirect to app topics |
| 18 | Ask the assistant to change your plan | Explains it can't; offers the team |
| 19 | Stop Ollama on the VPS (`systemctl stop ollama`), ask a question | Backup model answers (admin shows "(backup)"); restart Ollama after |
| 20 | Signed out, open Chat support | Asked to sign in |

Also check: first reply time on the VPS (admin shows the model per reply). If replies regularly
take more than ~20 s, lower `num_ctx`, cut article length, or move to a VPS with more CPU.
