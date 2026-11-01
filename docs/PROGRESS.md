# Project Progress — WhatsApp AI Agent (Lebanese SMB)

_Last updated: 2026-10-21. Based on a full read of every doc, backend module, n8n workflow and dashboard page, plus a local run (WHATSAPP_DRY_RUN=true) and an end-to-end Postman chat test._

Legend: ✅ built & verified · 🟡 built, not fully verified / partial · ❌ not built

---

## 1. Summary

| Layer | State |
|---|---|
| FastAPI backend (`agent-api/`) | ✅ Feature-complete for Phases 2–4.6 except follow-ups (#9). Runs, authenticates, dispatches (verified). |
| PostgreSQL | ✅ All tables in `agentdb`, seeded (4 businesses, 9 tools, 16 plan↔tool rows). Ad-hoc `migrate_*.py` scripts, no Alembic. |
| n8n workflows (`workflows/`) | 🟡 Phase 4 inbound **published and verified** end-to-end via Postman with Groq `qwen/qwen3.8-27b` (old `llama-3.3-70b-versatile` retired); scheduler active. Session memory + summaries (phases 1-2) live; Session Closer workflow active. |
| Admin dashboard (platform admin, `admin-dashboard/`, port 3100) | ✅ 18 pages (incl. Customers, Analytics, Audit log, Onboarding wizard + requests). |
| Business portal (business owners, `business-portal/`, port 3200) | ✅ Separate Next.js project and login: Overview, Conversations, Appointments, Orders, Needs attention, Subscriptions (read-only), Settings, public Onboarding form. Sees only its own business. |
| WhatsApp (Meta Cloud API) | 🟡 Code + test-number creds exist; webhook not public; templates approval unknown. |
| Deployment (VPS/Docker/nginx) | ❌ Nothing exists — deferred, see `DEFERRED.md`. |

**Overall: roughly 70% built (estimate, not measured).** Reactive agent works; most proactive pieces exist but haven't run against real WhatsApp. Remaining: memory, hardening, deployment, Meta go-live.

---

## 2. Phase-by-phase status

| Phase | Description | Status | Evidence |
|---|---|---|---|
| 1 | Local n8n workflow | ✅ | superseded by `workflows/inbound.json` (legacy file deleted 2026-10-22) |
| 2 | FastAPI multi-tenant API, config + conversation logging | ✅ (Redis ❌) | `routers/clients.py`, `conversations.py` |
| 3 | Tools: booking, orders, order status, escalation, after-hours | ✅ | tool nodes, `Build Prompt` node |
| 3.6 | Google Calendar (optional) | ❌ | — |
| 4 | Meta Cloud API inbound/outbound + verify | 🟡 | `inbound.json`, `whatsapp_client.py`, `routers/whatsapp.py`; needs public URL + Meta config |
| 4.5 | Proactive foundation (queue, dispatcher, templates) | 🟡 | `scheduled_messages`, `proactive.py`, `scheduler.json`; outbound lives in backend (`/whatsapp/send`); templates need Meta approval |
| 4.6 | Proactive capabilities | 🟡 | §3 (#9 missing) |
| 5 | VPS deployment | ❌ | — |
| 6 | Onboarding (form + prompt generator) | ✅ | `prompt_generator.py`, `routers/onboarding.py`, admin `/onboarding`, portal `/onboard` |
| 7 | Admin dashboard + business portal | ✅ | `admin-dashboard/app/*`, `business-portal/app/*`, `routers/portal.py` |

---

## 3. Agent capabilities and actions

| # | Capability | How it works | Status |
|---|---|---|---|
| 1 | FAQ & inquiry | System prompt; replies in Arabic/French/English | ✅ verified |
| 2 | Appointment booking | `book_appointment` → `/appointment/create`, plan-gated | ✅ built (re-test with new model) |
| 3 | Appointment reminders | Dispatcher queues N hours before; template message | ✅ built, not tested live |
| 4 | Subscription reminders | Owner enters subscribers in dashboard; dispatcher sends | ✅ verified (dry-run) |
| 5 | Order taking | `create_order` | ✅ built (re-test) |
| 6 | Order status | `get_order_status` (pull) + push on status change | ✅ built |
| 7 | Human escalation | `escalate_to_human` logs + queues owner WhatsApp alert | ✅ built |
| 8 | After-hours | `Build Prompt` node, Beirut-time opening hours | ✅ built |
| 9 | Follow-up messages | `followup_*` columns + `follow_ups` catalog entry only | ❌ |

**Actions the agent cannot do yet:** remember earlier messages · cancel/reschedule a booking · edit/cancel an order · Google Calendar / email · handle images/voice/documents (text-only) · hand a conversation to a human and pause the bot.

---

## 4. Component status

| Component | Done | Missing |
|---|---|---|
| Backend API | Auth, clients, tools/plans, orders, appointments, escalations, subscriptions, outbox, dispatch, audit, endpoint auth, history fix, slot availability, plan usage limits, analytics | Tests |
| Database | All tables, seeded | Alembic, backups, encrypted access token |
| n8n | Inbound (published, session memory + secret header), scheduler (active) | Instant 200 + de-dup, signature check, error alerts |
| Dashboards | Admin 18 pages, business portal 9 pages | Portal: add/edit subscribers, edit the prompt; upgrade Next.js (14.2.0 has a published security advisory) |
| Meta/WhatsApp | Code, test creds, dry-run | Public webhook, template approval, permanent token, real-number onboarding |

---

## 5. Production checklist

**Blocking a real client**
- [x] Conversation memory — v1 2026-10-21 (last 10 msgs / 24h), **replaced 2026-10-22 by session-based memory, phase 1** (`docs/SESSION_MEMORY_PLAN.md`): sessions per customer with a 4h idle rule, n8n `Resolve Session` node feeds the whole current session to the agent. Verified (13 API tests incl. parallel race, plus a live 2-turn webhook test).
- [x] Session memory phase 2 — DONE 2026-10-22: `/session/close-idle|transcript|summary`, n8n **Session Closer** workflow (every 10 min, Groq) writes a summary per closed session; the next new session gets the last 3 summaries. Verified live.
- [x] Session memory phase 3 — DONE 2026-10-22: `customer_profiles` (filled by the summarizer), absolute dates in summaries, dashboard **Customers** page (profiles, sessions, transcripts, edit, forget), per-business idle-timeout setting. Dashboard now has 14 pages.
- [x] Close `/auth/create-admin` (open only while no admin exists) and secure order/appointment/conversation/client endpoints — DONE 2026-10-21 (`agent-api/security.py`: internal secret for n8n OR admin JWT for dashboard; order/appointment status updates are admin-only). All n8n API calls now send `X-Internal-Secret`.
- [ ] Webhook returns 200 immediately and de-duplicates on message ID
- [ ] Verify Meta `X-Hub-Signature-256`
- [ ] Rotate secrets (`SECRET_KEY`, `INTERNAL_API_SECRET`, `VERIFY_TOKEN`, `admin123`) and the Meta token currently in `.env`
- [ ] Validate `qwen/qwen3.8-27b` in all 3 languages (tool calling verified; `<think>` reasoning is now stripped from replies, 2026-10-22). Known: Groq rate-limits ("too many requests") make a turn fail silently — add a fallback reply / retry

**Meta / WhatsApp**
- [ ] Public HTTPS webhook (ngrok for testing, domain for production)
- [ ] Submit/approve 5 templates: `appointment_reminder`, `subscription_reminder`, `order_status_update`, `escalation_alert`, `follow_up_generic`
- [ ] System-user permanent token (not the 24h one)
- [ ] Turn off `WHATSAPP_DRY_RUN` for real sends
- [ ] Template language hard-coded to `en`

**Deployment**
- [ ] Dockerfiles (API, dashboard) · `docker-compose.yml` (n8n, API, Postgres, Redis, dashboard, nginx)
- [ ] VPS (Hetzner), domain, DNS, Let's Encrypt
- [ ] n8n on Postgres with fixed encryption key; workflows re-imported; credentials re-entered
- [ ] Deploy script, DB backups, `/health` monitoring, log retention

**Product**
- [x] Plan usage limits — DONE 2026-10-22: customer messages per calendar month (business timezone), 500 / 2000 / unlimited by default, editable on the Plans page (`plan_limits` table). `/session/resolve` reports `usage.limit_reached`; n8n `Limit Reached?` branch replies with a fixed trilingual "contact the business" message and skips the AI.
- [x] Slot availability — DONE 2026-10-22: `GET /appointment/availability` + `check_availability` agent tool; `POST /appointment/create` rejects past / closed / outside-hours / taken slots with 409 and suggested slots. Per-business slot length and capacity on the business edit page. Naive times are treated as business-local.
- [ ] Follow-ups (#9) — deferred, see `DEFERRED.md`
- [x] Analytics + audit pages — DONE 2026-10-22: `/analytics` (all-businesses table with usage meters; per-business tiles, daily charts, status breakdowns, tool calls) and `/audit` (filterable tool-call log).
- [x] Onboarding + business portal — DONE 2026-10-22: structured onboarding form (services/prices, hours, FAQ, policies, tone, languages) → deterministic prompt generator (editable preview) → one-click business creation (plan-limited tools, WhatsApp number, portal login with one-time password). Prospects can submit the same form publicly at the portal's `/onboard`; admins review/approve/reject under Onboarding → Requests. Business owners get their own site and login (`business_users`), separated by a `role=business` JWT that every admin/internal endpoint rejects.
- [ ] Billing (OMT/Whish), self-service portal · Alembic migrations · automated tests

**Deferred (see `DEFERRED.md`):** Meta/WhatsApp go-live (webhook de-dup + signature, templates, tokens, secret rotation), Docker + VPS deployment, follow-up messages.

**Done so far:** ~~memory v1 → security fixes → session memory (phases 1-3) → slot availability, usage limits, analytics, audit → onboarding + business portal~~.

---

## 6. Issues found in the audit

| Severity | Issue | Location |
|---|---|---|
| ✅ Fixed | ~~`POST /auth/create-admin` open to anyone~~ | `routers/auth.py` |
| 🔴 High | Real Meta creds + `WHATSAPP_DRY_RUN=false` in `agent-api/.env`; default secrets and seeded `admin@example.com / admin123` | `.env`, `seed.py`, workflow JSON |
| ✅ Fixed | ~~Unauthenticated order/appointment/conversation/client endpoints~~ (`GET /order/{id}` and `GET /appointment/{id}` now only return the asking customer's own records to the agent; admins see all) | routers |
| 🟠 Med | Meta `X-Hub-Signature-256` never verified | n8n inbound |
| 🟠 Med | Workflows call `host.docker.internal:8000` (works inside Docker Desktop containers) | `workflows/*.json` |
| 🟡 Low | `GET /subscription/plans` hard-coded, disagrees with DB `plan_tools` | `routers/subscriptions.py` |
| 🟡 Low | Naive/aware datetime mixing; Beirut TZ not applied to reminder text | `appointments.py`, `proactive.py` |
| 🟡 Low | Dispatch retries have no back-off; concurrent dispatchers could double-send (no row lock) | `proactive.py` |

---

## 7. Local environment

| Component | State / notes |
|---|---|
| Python 3.11, Node 24 | ✅ |
| PostgreSQL 17 (native, shared with ~20 other projects) | ✅ `agentdb` migrated + seeded |
| Redis (native) | ✅ running, unused by the app |
| Port 3000 | ⚠️ used by another project (accounting-system) → dashboard on **3100**; CORS via `CORS_ORIGINS` env |
| Docker Desktop | ⚠️ WSL disk lives on **E:** (junction `…\Docker\wsl\disk → E:\docker\wsl\disk`); Docker won't start unless E: is connected |
| n8n | Container `n8n` (`n8nio/n8n`, port 5678, volume `n8n_data`); use **http://127.0.0.1:5678** (`localhost:5678` times out here); workflows imported, secrets patched from `.env` |
| Groq | Credential added in n8n; model `qwen/qwen3.8-27b` |
| ngrok | Binary at `C:\ngrok`; only needed for real Meta webhooks |

### Run everything (safe mode, no real WhatsApp sends)
```powershell
# 1. API  (http://localhost:8000/docs)
cd agent-api
$env:WHATSAPP_DRY_RUN='true'; $env:CORS_ORIGINS='http://localhost:3100,http://localhost:3200'
python -m uvicorn main:app --host 0.0.0.0 --port 8000

# 2. Dashboard  (http://localhost:3100 — admin@example.com / admin123)
cd admin-dashboard; npm run dev -- -p 3100

# 2b. Business portal  (http://localhost:3200 — demo owner login for Test Clinic: owner@example.com)
cd business-portal; npm run dev          # port 3200; the API must allow both origins:
#   $env:CORS_ORIGINS='http://localhost:3100,http://localhost:3200'

# 3. n8n  (http://127.0.0.1:5678) — Docker Desktop + E: must be up
docker start n8n
```

### Test the agent (Postman)
`POST http://127.0.0.1:5678/webhook/whatsapp`, JSON body `{"message_text": "...", "from": "96170000099", "to": "96171000002"}` (`to` = business WhatsApp number; `96171000002` = Test Clinic).

### Note: workflow secrets
`workflows/inbound.json` in the repo keeps the placeholder `change_me_internal_secret` in every `X-Internal-Secret` header. The live n8n copy has the real value from `agent-api/.env`. When re-importing, replace the placeholder first (and re-select the Groq credential). Re-importing the repo file overwrites the live workflow's credential link.

---

## 8. Design system (`@mostafa-hussein-dev/ui`) — added 2026-10-23
Both frontends (`admin-dashboard`, `business-portal`) now use the shared Systemize UI instead of hand-written Tailwind v3 pages.

- **Stack change:** Next.js 14.2.35 · Tailwind v4 via `@tailwindcss/postcss` (no `tailwind.config`; `app/globals.css` = `@import 'tailwindcss'` → `@import '@mostafa-hussein-dev/ui/styles.css'` → `@source …/ui/src`) · `next.config.js` has `transpilePackages` because the package ships TypeScript source.
- **Install:** the package is installed from the local copy (`file:C:/Users/MostafaHussein/Desktop/systemize-ui`) with `install-links=true` in each project's `.npmrc`, so it is copied (not symlinked) and React is not loaded twice. When the package is published to GitHub Packages, switch the dependency to a version and keep the `.npmrc` registry line; installing from GitHub needs a `read:packages` token in the user `.npmrc`.
- **Chrome:** `AppShell` is mounted in `components/app-frame.tsx` (loaded client-only via `app-frame-loader.tsx`). The admin nav is fixed; the portal nav hides pages the plan has no tool for.
- **Things to add to the package (so apps stop working around them):** (1) `useTheme`/`getInitialTheme`/`useLocalStorageState` touch `localStorage`/`matchMedia` during render, so the shell cannot be server-rendered (apps wrap it in `dynamic(..., { ssr: false })`); (2) `PasswordField` requires `showLabel`/`hideLabel`; (3) no chart colour tokens (charts use `--info` and `--brand`); (4) an optional dependency on `lucide-react ^1` forces apps to be on the same major.
- **Removed:** `components/navbar.tsx`, `lib/utils.ts`, and the unused `clsx`, `tailwind-merge`, `class-variance-authority`, `jwt-decode` dependencies.

---

## 9. Cancel / reschedule, AI-failure fallback, conversation layout — added 2026-10-23
- **Appointment cancel and reschedule (agent):** new tools `list_my_appointments`, `cancel_appointment`, `reschedule_appointment` (endpoints `GET /appointment/mine`, `POST /appointment/{id}/cancel`, `POST /appointment/{id}/reschedule`; gated by the `appointments` tool). Rules: the customer's own bookings only; only `pending`/`confirmed`; not in the past; a notice period (`businesses.appointment_change_notice_hours`, default 2, set by the owner in Settings or by the admin in the business form; migration `migrate_add_change_notice.py`); the new time goes through the same hours/capacity check as booking (a booking never blocks its own move); the reminder is re-armed after a move. Refusals are 409s with a message the agent relays (`too_late`, `not_changeable`, `slot_unavailable` + suggested slots, `same_time`). The owner gets a WhatsApp alert (outbox) on every customer cancel/move.
- **Business side:** `PUT /appointment/{id}/move` (admin) and `PUT /portal/appointments/{id}/move`; "Move" button + modal on both Appointments pages (times in the business timezone, no notice rule). Cancelling there is the existing status dropdown.
- **AI failure fallback:** the AI Agent node retries (2 tries, 5 s apart; the Groq model also retries 4×). If it still fails, the error branch calls `POST /session/agent-failure`, which stores the customer's message and a fallback reply in the session, adds a "Needs attention" item and alerts the owner (once per customer per 10 min), then n8n sends the fallback (Arabic if the customer wrote Arabic). Tested live: a rate-limited turn gets the fallback and the next one succeeds.
- **Known limit:** the Groq free tier allows 7,000 input tokens/min for `qwen/qwen3.8-27b`; one tool-using turn costs ~2.4k tokens per LLM call, so two or three turns a minute exhaust it. The fallback covers this; the real fix is the Groq Dev tier or a smaller prompt.
- **Conversations pages (both apps):** one row per session (customer, status, summary, message count, last message); clicking opens `/conversations/{id}`, a chat view with bubbles, day dividers, times in the business timezone and the summary on top. Shared `components/chat-thread.tsx`.
- **Deferred (see `DEFERRED.md` items 4–7):** automated test suites, Alembic, secrets/password rotation, portal self-service (subscribers, prompt, forgot-password, billing).

### 9.1 Mid-flow failure reply and order cancellation
- `POST /session/agent-failure`: if the customer had already written earlier in the session, the fallback says their details are saved and to resend; the owner alert and "Needs attention" entry carry their last few messages.
- `POST /order/{id}/cancel` + n8n tool `cancel_order`: customer cancels their own pending/confirmed order (ownership checked, owner alerted, later statuses refused with a message).
- Still open: telling a customer the business moved their booking (needs Meta go-live), editing an order's items.
- n8n note: close the n8n editor before importing the workflow; an open stale tab autosaves over the import.

### 9.2 Order editing and confirm-first rule
- `POST /order/{id}/edit` + n8n tool `edit_order`: customer replaces the full items list (and optionally notes) of their own order. Only while status is `pending` (409 `not_editable` otherwise); empty items or qty < 1 give 422; ownership checked; owner alerted on WhatsApp. Order item `price` is now optional.
- Confirmation rule (Build Prompt `[CONFIRMATION RULE]` + tool descriptions): cancel_order, edit_order, cancel_appointment and reschedule_appointment are never called on the customer's first message; the agent states the change and waits for a yes. This is a prompt instruction, not enforced in code.
- `cancel_appointment` refuses (409 `use_reschedule`) when the agent's reason is a time change, after the agent once cancelled a booking instead of moving it.
- Tool descriptions for `orders` and `appointments` list cancel/edit/reschedule so the model knows it can do them.
- Language rule fix: replies follow the customer's latest message language; the Lebanese Arabizi examples apply only when the customer writes Arabic/Arabizi.
- Known: on the Groq free tier a rate-limited reply can follow an action that already succeeded.

### 9.3 list_my_orders
- `GET /order/mine` + n8n tool `list_my_orders`: the asking customer's 10 most recent orders (id, status, items, notes, `can_edit`, `can_cancel`); phone matched by digits; empty list for unknown numbers. The orders tool description tells the agent to call it when the customer does not know the order number.
- Verified against the API only. The live agent call was not verified: on the Groq free tier each model call is now about 4.7-5k input tokens against a 7,000/min cap, so tool turns rate-limit almost every time. Recheck on the production LLM (DEFERRED item 9).

### 9.4 LLM switched from Groq to OpenAI
- `inbound.json` ("OpenAI Chat Model") and `session_closer.json` ("OpenAI Summary Model") now use the n8n `lmChatOpenAi` node (v1.3), model `gpt-5-mini` as a placeholder, `maxRetries` 4, no temperature set (the gpt-5/gpt-6 families only accept the default). Output limits were raised to 1000/1200 tokens because reasoning tokens count against them.
- Credential: n8n credential "OpenAI account" (id `openAiCred01`, type `openAiApi`) was created with the placeholder key `REPLACE_WITH_YOUR_OPENAI_KEY`. To go live: n8n > Credentials > OpenAI account > paste the real key; then pick the model in the two model nodes.
- Until the real key is added every agent call fails and customers get the AI-failure fallback message.
- Model research (official pricing, USD per 1M tokens in/out): gpt-6-luna 0.10/0.50, gpt-5-nano 0.05/0.40, gpt-5-mini 0.25/2.00, gpt-5.4-mini 0.75/4.50, gpt-6.1-sol 2.00/10.00. No public benchmark covers Arabic dialect tool calling, so test our own scenarios.

### 9.5 Arabizi policy, plain-text replies, mixed-script display
- Arabizi is understood but never written. `ARABIZI_POLICY` at the top of the language block in the `Build Prompt` node of `inbound.json` chooses what happens when a customer writes Arabizi: `'arabic'` (default: reply in Arabic script in the business dialect), `'english'`, or `'ask'` (one bilingual question, then follow the answer).
- New `Clean Reply` node (after AI Agent): removes markdown (bold, headings, backticks, `*` bullets) and, in Arabic replies, wraps each Latin run (product names, order numbers, prices) in Unicode isolates (LRI/PDI) so it keeps its own left-to-right order. Log, send and webhook response all use its output.
- A `[FORMATTING]` prompt rule asks for plain text with dashes and colons only; Western digits in Arabic replies; Latin names kept out of the middle of Arabic sentences.
- Short confirmations (eh, aywa, tamam, yalla, ok, نعم) count as yes; the agent never asks for a specific word.
- Both portals' chat bubbles use `dir="auto"`.
- Business portal dashboard: "Messages per day" now sits in the same chart grid as the other charts.
- Models: `inbound.json` is pinned to `gpt-6-luna` (maxTokens 2500) and `session_closer.json` to `gpt-5-nano`. Importing a workflow resets the model nodes to what is in the file, so keep these in sync with what is chosen in n8n.

### 9.6 Arabic replies are formal Modern Standard Arabic
- The business-dialect rule (Lebanese etc., Maghrebi banned list) was removed from `Build Prompt`. Every Arabic reply, including replies to Arabizi, is formal, professional Modern Standard Arabic with simple wording. `ARABIZI_POLICY` is still `'arabic'`.

### 9.7 One source of truth for business facts, one escalation per session, closed-day alerts
(The placeholder/template mechanism described here was replaced by 9.8; the escalation and alert-timing parts still apply.)
- **Prompt = template + settings.** `businesses.system_prompt` is a template; `{{HOURS}}`, `{{ADDRESS}}`, `{{PHONE}}`, `{{WEBSITE}}`, `{{SERVICES}}`, `{{POLICIES}}`, `{{FAQS}}` are filled in at run time (`prompt_generator.render_prompt`, used by `/client/config/{id}` for n8n) from `opening_hours` and the new `businesses.profile` JSON. Lines whose placeholder is empty are dropped. New businesses (onboarding) get a template and a profile. Prompts that still type the hours get an authoritative `[BUSINESS HOURS]` block appended, so the settings win.
- **Admin edit page:** "Business information" editor (location, phone, website, services and prices, policies, FAQs); a warning when the prompt has facts typed in as text (red when they disagree with the settings) with an **Update prompt** button (`POST /client/{id}/prompt-fix` swaps them for placeholders and keeps the typed values in the profile); "Show what the assistant sees" (`GET /client/{id}/prompt-preview`). Opening hours are still edited in the business portal Settings.
- Existing prompts were converted (all 5 businesses). Systemize's prompt said Saturday closes at 13:00 while its settings said 18:00; it now follows the settings.
- **One escalation per session:** `session_service.escalation_in_session`; a second escalation request (or AI failure) in the same session creates no record and no alert. Chat and replies are unchanged.
- **Next opening, not the whole week:** while closed, the escalation tool result and the config `closed_note` tell the agent when the team is next available ("tomorrow (Monday) at 09:00") and not to list the weekly hours.
- **Owner alert timing:** `businesses.escalation_alert_mode` = `immediately` | `when_open`. With `when_open` and the business closed, owner alerts (escalations, AI failures, customer order/appointment changes) are queued for the next opening time (`proactive.enqueue_owner_alert`). Editable in the admin edit page and the portal Settings.
- Migrations: `migrate_add_profile_alert_mode.py`.
- Prompts always carry every placeholder: `prompt_generator.ensure_sections` adds any that are missing (empty ones render to nothing), and `Update prompt` runs it. The checker also warns when the business information has a value (for example an FAQ) but the prompt has no placeholder for it.
- Manual removal of a placeholder cannot hide a fact: `render_prompt` appends any section (location/phone/website, services, policies, FAQs) that has a value in the business information but no placeholder in the prompt. The edit page still warns about it and `Update prompt` puts the placeholder back.

### 9.8 The prompt is view-only and built from the business information
- The system prompt is no longer written or edited by hand. `prompt_generator.render_prompt(business)` builds it every time from the business's fields: name and type, `profile` (description, languages, tone, address, contact phone, website, services and prices, policies, FAQs, extra instructions), `opening_hours`, `escalation_number`, and the enabled tools (appointments / orders decide the "how you work" lines). `/client/config/{id}` (used by n8n) renders it live; `businesses.system_prompt` is only a stored copy rebuilt on every admin save, portal settings save, plan change and onboarding.
- Admin: the onboarding page and the business edit page use the same form (`OnboardingFormFields`) and show the prompt read-only, refreshed as the form changes (`PromptView` calls `/onboarding/preview-prompt`). Opening hours are now editable in the admin edit page too. Anything typed as `system_prompt` in an API call is ignored.
- Removed as redundant: the placeholder system, the prompt check / Update prompt button, the separate "Business information" editor, the prompt text box on both pages, the "Add business" page (the button opens onboarding), the `prompt-check`, `prompt-fix` and `prompt-preview` endpoints, and the `system_prompt` override on onboarding.
- `migrate_prompt_from_info.py` moved the two existing businesses over. `seed.py` still sets old `system_prompt` strings, which are now ignored (seeded businesses get a generic prompt until edited).

### 9.9 Admin dashboard UI/UX pass
- **Shared pieces:** `lib/list-view.ts` + `components/list-toolbar.tsx` (search, filters, sort, paging for any in-memory list), `lib/use-businesses.ts` (picker defaults to "All businesses"; `useScoped` merges one list across businesses), `PageHeader back=` (back arrow), pages sit in an 80%-wide container (`app-frame.tsx`).
- **Lists with search / filters / sort / paging and an "All businesses" option:** conversations, orders, appointments, escalations, customer subscriptions, outbox, customers, businesses, onboarding requests, tools, analytics (all-businesses table). The audit log already paged on the server. Lists fetch up to 1000 rows per business (500 for some), then page in the browser.
- **Back arrows** on every sub-page (edit business, onboarding, requests, conversation chat); "Requests from businesses" sits beside "Add business"; the "New onboarding" button on the requests page is gone.
- **Save buttons only appear after a change:** edit business (with Discard), customer profile, plans (per plan), tool edit window. The WhatsApp number actions no longer reset unsaved edits.
- **Dashboard:** KPI tiles (businesses, customers, ongoing conversations, pending escalations, pending orders, upcoming appointments, outbox, denied tool calls), messages-per-day chart for all businesses, monthly plan usage per business, alerts (inactive subscriptions, missing/disabled WhatsApp numbers, plan limits near or reached, failed outbound, failed summaries, denied tool calls), panels for escalations / ongoing conversations / appointments / orders, and a per-business table. 7/30/90-day range.
- **Customers:** the list now includes customers who only have an ongoing conversation (a profile is created from a finished conversation's summary, so they used to be missing: 40 of Systemize's 60 customers). "Forget customer" sits at the top beside "All customers". `GET /customer/list/{id}` returns `has_open_session` and `last_activity`.

### 9.10 Follow-up messages (capability #9)
- **On/off:** `businesses.followup_enabled` + `followup_delay_hours` (edit business form) and the `follow_ups` tool (enterprise plan). Both must be on.
- **Two triggers** (`proactive.generate_followups`, run by the dispatch cycle): (1) *abandoned chat*: the customer's latest session went quiet `delay` hours ago after at least two customer messages and produced no order, appointment or escalation; (2) *visit*: an appointment (not cancelled / moved / no-show) whose time passed `delay` hours ago. A trigger older than delay + 72 h is dropped.
- **Stop conditions:** customer opted out; customer wrote again since; this trigger already handled (`scheduled_messages.ref` = `session:<id>` / `appointment:<id>`); any follow-up to that customer in the last 7 days. Outside opening hours the message is held until the next opening.
- **Message:** template `follow_up_generic` (params: name, business); the fallback text is Arabic or English from the customer's profile language. It must be an approved Meta template at go-live.
- **Opt-out:** the agent tool `stop_followups` -> `POST /customer/opt-out` (table `message_opt_outs`, survives "forget customer"); pending follow-ups for that customer are cancelled. Reminders for their own bookings are unaffected.
- **Audit:** every follow-up is a row in the Outbox page (kind "Follow-up"). Migration: `migrate_add_followups.py` (run).

### 9.11 Owner self-service in the business portal
- **Customer subscribers** (portal "Customer subscriptions"): add, edit, pause / resume, cancel, delete. The phone is normalised to digits (8-15), a new due date cannot be in the past, the same customer cannot have the same active service twice, and the due date is 09:00 on the chosen day in the business timezone. Needs the `subscription_reminders` tool (403 with an explanation otherwise). Resuming a paused subscription moves a past due date to the next cycle. Routes: `POST/PUT/DELETE /portal/subscriptions`.
- **Plan & billing** (portal page `/billing`): current plan, price and this month's usage; the three plans side by side; "Switch to" shows what is gained and lost, the new message limit and a warning when this month's usage is already over it, then sends a request (one pending request at a time, the owner can cancel it). Plan history and invoices are listed.
- **Admin:** "Plan requests" page (approve / reject with a note; approving applies the change at once: tools the new plan lacks are switched off, tools it adds are switched on, the prompt is rebuilt; optional invoice for the plan price), "Invoices" page (create, mark paid / void / reopen, total unpaid), monthly price per plan on the Plans page, and a dashboard alert for pending requests. Plan changes made on the business page are recorded in the same history.
- **Data:** tables `plan_change_requests`, `invoices`; `plan_limits.monthly_price`. Migration `migrate_add_billing.py` (run). Logic in `billing.py`; routes in `routers/portal_billing.py` and `routers/admin_billing.py`.
- **Tested** on a throwaway business (deleted after): 27 checks on the API, including that an owner token cannot reach admin routes and that one business cannot touch another's rows. The pages compile and return 200; not viewed in a browser by me.

### 9.12 Logging, audit and security tracking (phases 0 and 1)
- **Foundation (`auditlog.py`, middleware in `main.py`):** every request gets a trace id (header `X-Trace-Id`, returned in the response; n8n can send its own later). One row per request in `api_requests` (route template, status, time, caller; never the body). A background thread writes everything in order, and each record is also written first to `agent-api/logs/api.jsonl` (rotating, 10 files of 10 MB). Secrets (password, token, secret, api key...) are masked, the system prompt is stored as a length, and request bodies are captured only for logged-in admins and owners, never for the n8n calls that carry customer messages.
- **Security events (`security_events`, hash-chained):** admin and portal logins (success, failure, which account), lockout (10 failures in 10 minutes per account gives HTTP 429), password changes, invalid tokens, a business token used on an admin route, wrong internal secret, owner lookups of missing or foreign records, server errors, and sensitive actions (delete business, WhatsApp number and portal user changes, credential or alert-number changes, forget customer, tool delete, manual dispatch, new admin).
- **Audit trail (`audit_events`, hash-chained):** every change made by an admin or owner (who, what, when, record, result), with old -> new values for business edits, owner settings, plan tools, plan limits and prices; the other changes list the fields that were sent. Opening a conversation transcript is recorded too.
- **Integrity:** each record includes the hash of the previous one; `POST /admin/security/verify` (button on the Security page, also daily) detects an edited or removed record.
- **Retention in force:** request log 30 days, job runs 90, security events 400, audit trail 730; IP address and browser are removed from security and audit rows after 90 days (they are outside the hash, so the chain stays valid). Customer-data retention is deferred (DEFERRED 11).
- **Alerts (dashboard + Security page):** 5+ failed logins for one account in 10 minutes, lockouts, business logins on admin routes, 10+ foreign-record lookups in 10 minutes, 10+ server errors in 10 minutes, 3+ wrong internal secrets, an admin signing in from a new address, a failed chain check.
- **Admin pages:** "Security" (alerts, integrity and retention status, filterable event list) and "Audit trail" (filters, old -> new values); the old "Audit log" page is now called "Tool-call log". Endpoints under `/admin/security/*` and `/admin/audit-trail/events`.
- **Tested:** 33 checks (logins, lockout, token and role misuse, masking in the database and in the log file, audit with before/after, internal calls not captured, tamper detection and recovery, retention and IP stripping with the chain still valid). The test records were cleared afterwards, so the logs start empty.

### 9.13 Agent turn tracing (logging phase 2)
- **Turn log:** one `agent_turns` row per customer message: the customer text and detected language (arabic / arabizi / english / mixed), the reply (and the model's text before the clean-up step when it differs), every tool called with its arguments and result, whether it worked, escalation, model, token counts, cost, total time and time in the model, automatic flags (`tool_error`, `fallback_reply`, `escalated`, `empty_reply`, `plan_limit_reached`). Replies cut short by the plan limit and by an AI failure are logged too (outcomes `limit` and `error`).
- **How it is written:** the inbound workflow's new `Build Turn Log` + `Log Turn` steps run after the reply is sent (a failure there cannot stop the reply), `Log Limit Turn` covers the plan-limit path, and `/session/agent-failure` logs the error path itself. The AI Agent step now returns its intermediate steps (the tool calls).
- **One trace id per turn:** every API call the workflow makes carries `X-Trace-Id: n8n-<execution id>`, so a turn, its request-log rows, its audit events and the n8n execution are linked. Verified: the opt-out chat shows `session/resolve`, `customer/opt-out`, two `conversation/log`, `whatsapp/send` and `internal/turn` under one id.
- **Tokens and cost are estimates for now.** The AI Agent step does not expose the real token usage to the workflow (n8n keeps it only in its own execution history), so the server estimates from the prompt size, the tool results and the reply (`turns.py`, flagged `token_source: estimated`; the first calibration is a plain-text 3.3 characters per token). Cost uses the model's list price (`turns.MODEL_PRICES`). To get real numbers later: an n8n API key so the server can read token usage from the execution after the fact. The first attempt to read the model sub-node from the workflow made the step hang; it was removed (do not reintroduce `$('OpenAI Chat Model').all()`).
- **Model name** is a constant in the `Build Prompt` step (`model: 'gpt-6-luna'`, next to `workflow_version`); keep it equal to the model chosen in the OpenAI Chat Model node, and bump `workflow_version` when the rules in that step change.
- **Prompt versions:** `prompt_versions` stores each distinct business prompt with who changed it and the trace of that change (recorded when a business is edited, its plan or settings change, or it is onboarded; and the first time a turn sees it). Every turn links to the version it used.
- **API and page:** `POST /internal/turn`, `GET /admin/turns` (filters), `/admin/turns/{id}`, `/admin/turns/stats` (turns, tokens, cost, latency per business and day), `/admin/prompt-versions`. Admin page "Agent traces" (list, search, filters, expandable detail with tool calls, the prompt used, tokens, cost and time). The fuller explorer, flag filter and health views are phase 3.
- **Opt-out test:** now passes. The agent called `stop_followups`, the opt-out was recorded, and the reply was a short confirmation. The earlier failures were because my stronger prompt rule had never actually reached n8n (the import silently did not apply); every deploy is now verified by exporting the live workflow and checking for the new text.

### 9.14 System health, trace explorer and "not sent" log (logging phase 3)
- **System health page** (`/health`, `GET /admin/health`, refreshes every 30 s): scheduled jobs (dispatcher expected every 5 min, session closer every 10; each shows last run, runs, failures, "late" when overdue), log clean-up and integrity-check status, outbox (waiting now, held for later, sent and failed in 24 h, age of the oldest waiting message), assistant (replies, error fallbacks, reply time p50 / p95, tool-error rate, plan-limit hits, open chats, summaries waiting / failed), API (requests, 4xx / 5xx, p50 / p95, slowest routes), skipped counts by reason, log sizes. Jobs report in through `job_heartbeats` (`auditlog.heartbeat`, called by the dispatch cycle and `/session/close-idle`).
- **New alert rules** (Security page, dashboard, health page): 20%+ of the last hour's replies were the error fallback (5+ replies), 95% reply time over 30 s, 25%+ of tool-using replies had a tool error, dispatcher silent over 15 min, session closer silent over 30 min, queued messages overdue over 30 min, today's cost over 3 times the previous week's daily average.
- **"Not sent, and why"** (`proactive_skips`, `GET /admin/skipped-messages`, panel under the Outbox page and counts on the health page): one row per thing considered and not sent, with the reason and how many dispatcher runs looked at it: follow-ups (tool not in plan, customer opted out, customer came back, customer wrote after the visit, chat already ended in an order / booking / escalation, too few customer messages, followed up in the last 7 days), appointment and subscription reminders and order-status notices when the tool is not enabled. The row is removed if the message is later sent; rows older than 90 days are cleaned up.
- **Trace explorer** (Agent traces page): server-side flag filter, charts per day (turns, estimated cost, average reply time), and in each turn's detail the API calls made for that message, changes and security events under the same trace id (`GET /admin/trace/{trace_id}`), a button to open the whole conversation, and the business prompt used. `GET /admin/turns` also filters by `session_id`.
- **Not done (needs an n8n API key):** n8n execution results and real token counts. The health page counts the assistant's own replies instead.
- **Tested:** 17 checks on a throwaway business (every skip reason, no duplicates, heartbeats, stale-dispatcher alert, health, trace and skip endpoints); the test data and the heartbeats it touched were put back.

### 9.15 Tool scope: Tool activity page, Plan checks, opt-out audit
- **Tool activity** (admin page, `GET /admin/tool-activity/summary` and `/calls`): one row per assistant tool (all 12, including unused ones) with calls, failures, businesses, plan denials and last use; click a tool to list its calls with what was sent and what came back, filterable by business, result, period and text, with links to the trace and the conversation. Backed by a new `tool_calls` table written with every agent turn (`turns.save_tool_calls`); the table `turns.TOOL_PLAN_ENTRY` maps each tool to the plan feature whose check it passes (`stop_followups` has none: it is open to every plan). A tool added to n8n but not to that table still shows up in the list.
- **Plan checks:** the old "Tool-call log" is renamed; it records whether the plan allowed a feature (the denied rows are the useful part), not what the tool did.
- **Agent traces:** new "Tool used" filter with the 12 tool names.
- **Opt-out audited:** when the assistant records an opt-out, an audit event `customer.opt_out_followups` (actor: assistant) is written with the business and customer.
- **Tested live:** a chat that triggered `check_availability` and `stop_followups` produced both tool-call rows, the summary counts and the audit event.

