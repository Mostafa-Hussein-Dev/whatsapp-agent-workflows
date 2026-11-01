# Deferred work

Things that are designed or partly built but deliberately **not being worked on yet**. Each item says what exists, what is missing and why it waits. Moved here 2026-10-22; `PROGRESS.md` still tracks the overall checklist.

---

## 1. Meta / WhatsApp go-live

**Why deferred:** decided to finish the platform (agent, memory, dashboards) before connecting a real number. The agent is fully testable through the Postman webhook and `WHATSAPP_DRY_RUN=true`.

**What exists:** Meta Cloud API client (`whatsapp_client.py`), `/whatsapp/send`, webhook verify + inbound parsing in the Inbound workflow, the outbox + dispatcher, test-number credentials in `agent-api/.env`. See `WHATSAPP_SETUP.md`.

**Still to do**
- Public HTTPS webhook (ngrok for testing, a domain for production).
- Return `200` to Meta immediately and de-duplicate on the message ID (Meta retries; today a slow reply can produce duplicate answers).
- Verify `X-Hub-Signature-256` on inbound webhooks.
- Submit and approve the 5 templates: `appointment_reminder`, `subscription_reminder`, `order_status_update`, `escalation_alert`, `follow_up_generic`. Template language is hard-coded to `en`.
- System-user permanent token instead of the 24h token; onboarding of real client numbers.
- Turn off `WHATSAPP_DRY_RUN` for real sends.
- Rotate the secrets in `.env` (`SECRET_KEY`, `INTERNAL_API_SECRET`, `VERIFY_TOKEN`), the seeded `admin123` password and the Meta token currently stored there.
- A fallback reply when the model call fails (Groq "too many requests" currently produces no answer at all).

---

## 2. Docker and VPS deployment

**Why deferred:** features first; deployment once the product surface is stable.

**What exists:** nothing for production. Locally n8n runs in Docker Desktop, everything else runs natively (FastAPI on 8000, admin dashboard on 3100, business portal on 3200, shared PostgreSQL and Redis).

**To do**
- Dockerfiles: API, admin dashboard, business portal.
- `docker-compose.yml`: n8n, API, PostgreSQL, Redis, both frontends, nginx.
- VPS (Hetzner or similar), domain + DNS, Let's Encrypt, nginx with separate hostnames for admin and portal (e.g. `admin.` / `app.`).
- n8n on PostgreSQL with a fixed `N8N_ENCRYPTION_KEY`; re-import the three workflows (`inbound.json`, `scheduler.json`, `session_closer.json`) with the real internal secret and the Groq credential.
- Environment management: `CORS_ORIGINS` for both frontends, `NEXT_PUBLIC_API_URL`, production `SECRET_KEY`.
- Deploy script, database backups, `/health` monitoring, log retention.
- Replace the ad-hoc `migrate_*.py` scripts with Alembic before the first production deploy.

---

## 3. Follow-up messages (capability #9)

**Status:** built (see PROGRESS 9.10): abandoned-chat and after-visit triggers, stop conditions, opt-out tool, outbox audit. Tested in dry-run only.

**Still to do (depends on the Meta go-live, item 1)**
- Submit and get approval for the `follow_up_generic` template (params: customer name, business name) in each language served.
- Send a real follow-up end to end and check the 24-hour window handling.
- Optional later: personalise the text from the last session summary, a follow-up history view on the Customers page, a per-business choice of triggers.


---

## 4. Automated test suites

**Why deferred:** decided to finish features first.

**What exists:** throwaway scripts used during development (sessions, limits, slots, portal, cancel/reschedule). They live in a session scratchpad, not in the repo.

**To do**
- Move them into `agent-api/tests/` as a pytest suite with an isolated test database.
- Cover: auth and role separation, ownership checks, slot availability, usage limits, sessions and summaries, cancel/reschedule, onboarding and the portal.
- Workflow checks for `inbound.json` (a dry-run chat through n8n) and a UI smoke test for both frontends.

---

## 5. Alembic migrations

**Why deferred:** the ad-hoc `migrate_*.py` scripts work for local use.

**To do:** replace them with Alembic (baseline from the current models) before the first production deploy. See also item 2.

---

## 6. Secrets and password rotation

**Why deferred:** by choice, while everything is local.

**What exists:** the default `change_me_internal_secret` and `SECRET_KEY`, the `admin123` admin password, and the real Meta credentials in `agent-api/.env`.

**To do (before any deployment)**
- New `INTERNAL_API_SECRET` (in the API `.env` and in all three n8n workflows), new `SECRET_KEY`, new admin password.
- Rotate the Meta access token when the permanent token is created (item 1).
- Move secrets out of the workflow JSON into n8n credentials or environment variables.

---

## 7. Business portal: auth, users and multi-tenancy modules

**Status:** owner self-service is built (see PROGRESS 9.11): customer subscribers add/edit/pause/cancel/delete, plan-change requests with admin approval, plan history and manual invoices. The prompt stays view-only by decision (it is built from the business information).

**Deferred by decision:** the user has their own plan for the basic management / auth / user functionality, so these wait for it:
- "Forgot password" for portal logins (email link, expiry, throttling; needs an email service, SMTP or similar).
- Multi-tenancy and user management: several logins per business, roles and permissions, invites, admin users, session/token handling.
- Payment provider integration for billing (OMT / Whish): checkout, payment webhooks, automatic invoices and renewals. Billing today is manual: an admin issues an invoice and marks it paid.

---

## 8. Re-check dialect and Arabizi replies on the production LLM

**Why deferred:** the dialect rule was tuned against the free Groq model (`qwen/qwen3.8-27b`), which is weak at Levantine Arabic. It works there only with a banned-word list and Lebanese examples in the prompt.

**What exists:** a `[LANGUAGE - MANDATORY]` block in the `Build Prompt` node of `inbound.json`: Arabizi understanding (2/3/5/7/8/9), a default dialect from the business timezone, a Maghrebi banned-word list, and Lebanese Arabizi examples (Beirut businesses only).

**To do (when the production model is chosen and deployed)**
- Re-test with Arabizi, Arabic script, French and English messages for each dialect we serve (Lebanese first), including a mid-conversation language switch.
- Check that the replies are natural, not Maghrebi, and not a different dialect from the customer's.
- Check that the banned-word list and the examples are still needed. A stronger model may not need them, and the examples may even bias its replies.
- Add example sets for other regions if we serve them (Gulf, Egyptian, Syrian).


## 9. Replace the Groq free tier with the production LLM

**Why deferred:** decided to do it as part of deployment. Until then the agent runs on Groq `qwen/qwen3.8-27b`.

**What the free tier costs us**
- Capped at 7,000 input tokens per minute, and one tool-using turn needs about 2.4k tokens per model call, so action turns (cancel, edit, reschedule, book) often hit the limit and need several retries.
- The customer then sees the "technical problem" fallback, sometimes after the action already succeeded.
- It sometimes ignores instructions (says it cannot cancel orders, cancels instead of rescheduling, acts without confirmation) and is weak at dialects.

**To do:** pick a provider (Gemini Flash or Claude Haiku are the candidates), swap the model node in `inbound.json` and its credential, then re-run the agent flows (order create/edit/cancel, appointment book/reschedule/cancel with confirm-first, Arabizi). Related: item 8 (dialect recheck).

**Measured later:** each model call is now about 4.7-5k input tokens (system prompt with the tool policy, language/confirmation rules, 12 tools and the session history, including repeated fallback replies). A tool turn needs 2+ calls, so on the free tier it cannot fit in one 7,000-token minute. Worth trimming the prompt, and leaving the fallback replies out of the history sent to the model, if a small or metered model is chosen.

**Update:** the workflows now use OpenAI instead of Groq (see PROGRESS 9.4). The remaining to-do under this item is re-running the agent flows and the dialect check (item 8) on the chosen OpenAI model, and then trimming the prompt only if cost matters.

**Note for item 8:** the agent no longer writes Arabizi (`ARABIZI_POLICY` in `Build Prompt`, default `'arabic'`). On the production model, re-test that Arabizi input gets Arabic-script replies in the right dialect, and that the isolate marks added by `Clean Reply` display correctly in real WhatsApp (iOS and Android).


---

## 10. Real-conversation dataset to test and improve the agent

**Why deferred:** our own scenarios are written by us, so they do not match how real customers talk to an assistant they know nothing about (short, messy, impatient, mixed languages, changes of mind). Decided on 2026-10-27 to tackle it later, as an improvement step for the agent.

**What exists:** the research on candidate datasets is done (held by the user, not yet in the repo). A research prompt was written for this, covering real customer-to-business chats, task-oriented dialogue sets (appointments, orders, cancellations), Arabic / Lebanese / Arabizi sources, licences and privacy checks.

**To do**
- Put the research results in `docs/` (shortlist with licences) and pick the first 2-3 datasets.
- Convert them into test cases for our tools: map intents to book / reschedule / cancel / order / escalate, fill in business profile and opening hours, define the expected outcome per case.
- Build a scenario runner that replays them against the live agent and scores: tool choice and arguments, wrong actions (no confirmation, someone else's order), unnecessary or missed escalation, hallucinated hours or prices, language and dialect (no Arabizi in replies, formal Arabic), latency and cost.
- Validate any LLM-as-judge against about 50 human-labelled cases; run repeats because answers vary.
- Fill gaps (for example real Lebanese Arabizi customer chats) with consented chats from pilot businesses.
- Feed the failures back into the prompt and tool descriptions. Related: items 4 (automated tests) and 8 (dialect re-check).


---

## 11. Data retention for customer data (decided 2026-10-27: do it later)

**Why deferred:** by choice. For now these are kept without any limit. Settle each one before real customers use the system, because they hold personal data and some can contain sensitive details (for example health details at a clinic).

| Data | Where it lives | Proposed rule when we add it |
|---|---|---|
| Customer message text (conversations and, later, agent traces) | `conversations`, `agent_turns` | Per-business setting, default 180 days, then remove the text and keep anonymous statistics |
| Customer phone numbers inside traces and logs | traces, `api_requests.path` | Drop or hash when the text is dropped |
| n8n execution history | n8n's own database in the Docker container: a full copy of every run (phone, message, tool results, reply), outside our permissions and not touched by "Forget customer" | Turn on pruning (14-30 days); restrict who can open the n8n editor |
| Session summaries and customer profiles | `conversation_sessions.summary`, `customer_profiles` | Expire after a period of customer inactivity (for example 12 months) |
| Outbox message bodies | `scheduled_messages.body` | Keep the body 90 days, then only status and time |
| Escalation `last_message` text | `escalations.last_message` | Same rule as messages |
| Tool call arguments and results | `tool_calls.args`, `tool_calls.result` (phone numbers, names, order contents) | Same rule as messages |
| Review tags and JSONL export files | future review workflow | Anonymize before export; keep only the anonymized copy |
| Backups | future deployment | Expire on the same schedule |

Also needed: "Forget customer" must also remove the customer from traces and from the n8n history, and the business should be able to choose its own period. Check the Lebanese personal-data law (and GDPR for any EU customer) with a lawyer before fixing the numbers.

**Already in place (not deferred):** request log 30 days, security events 400 days (IP address and browser removed after 90), audit trail 730 days, job runs 90 days; run daily by the dispatch cycle (`auditlog.maintenance`).


## 12. Logging, audit and tracking: phases 2-5

Phases 0 and 1 are built (PROGRESS 9.12). Remaining, in order:
- **Phase 2: built** (PROGRESS 9.13). Still open from it: real token counts instead of estimates (needs an n8n API key to read the execution after the fact).
- **Phase 3: built** (PROGRESS 9.14). Still open from it: n8n execution results and real token counts (need an n8n API key: n8n Settings > n8n API).
- **Phase 4:** automatic gap signals (fallbacks, refusals, unanswered questions, failing tools, language mismatches, abandoned chats), the weekly gaps report, review tags (good / bad / gap) and the JSONL export.
- **Phase 5:** business-owner pages: Activity (changes in their account), What the assistant did (with a "this was wrong" button feeding the review queue), Insights (unanswered questions, funnel, topics), Delivery log, CSV export.

