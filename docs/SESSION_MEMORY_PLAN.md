# Session-Based Memory — Design & Plan (approved 2026-10-22)

## Concept
A **session** = one continuous exchange between one customer and one business, keyed by `(business_id, customer_phone)`.
A session stays open while messages keep arriving. When the customer has been idle for **4 hours** (`businesses.session_idle_minutes`, default 240, per business), the next message closes it and opens a new one.

Two kinds of memory reach the agent:
- **Current conversation** — the exact messages of the open session, on every message.
- **Customer history** — summaries of the last 3 closed sessions, injected **only when a new session starts** (not on every message).

## Flow
```
Customer msg → n8n
  1. POST /session/resolve      finds/opens the session (idle rule); returns session, is_new, messages, past_summaries (only if is_new)
  2. Build Prompt               system prompt + [CUSTOMER HISTORY] (new session only) + [CURRENT CONVERSATION]
  3. AI Agent replies
  4. POST /conversation/log x2  carries session_id; bumps last_message_at / message_count
Scheduler (every 10 min) "Session Closer" workflow:
  POST /session/close-idle → for each: GET transcript → Groq summarizes → POST /session/{id}/summary
```
Summarization runs in n8n (Option A): it already holds the Groq credential, and the API stays free of LLM dependencies.

## Data model
- `conversation_sessions`: `id` (uuid), `business_id`, `customer_phone`, `status` (open/closed), `started_at`, `last_message_at`, `closed_at`, `message_count`, `summary`, `summary_status` (pending/done/failed/skipped), `summary_attempts`.
  - Unique partial index: one `open` session per `(business_id, customer_phone)` (race-safe creation).
- `conversations.session_id` (nullable FK). Existing rows were backfilled by the idle rule.
- `businesses.session_idle_minutes` (default 240).
- Phase 3: `customer_profiles` (name, language, preferences, counts) updated by the summarizer.

## API (internal secret OR admin JWT unless noted)
| Endpoint | Phase | Purpose |
|---|---|---|
| `POST /session/resolve` | 1 ✅ | Find/open session; returns messages + (if new) past summaries |
| `POST /conversation/log` | 1 ✅ | Optional `session_id`; auto-attaches when omitted |
| `GET /session/{id}`, `GET /session/list/{business_id}` (admin) | 1 ✅ | Inspect sessions |
| `POST /session/close-idle` | 2 ✅ | Close idle sessions, queue summaries |
| `GET /session/{id}/transcript` | 2 ✅ | Messages to summarize |
| `POST /session/{id}/summary` | 2 ✅ | Store summary, status `done` |

## Summary rules (phase 2)
3–6 lines in the customer's language: what they wanted; what was decided/booked/ordered (with IDs); what is unresolved; customer name & preferences. No small talk, no invented facts. Sessions with < 2 messages are `skipped`. Failures stay `pending`, retried up to 3 times, then `failed`; a new session still works without the summary.

## Phases
| Phase | Scope | Status |
|---|---|---|
| 1 | Sessions table + migration/backfill, `/session/resolve`, log carries `session_id`, n8n `Resolve Session` replaces `Load History` | ✅ done 2026-10-22 |
| 2 | close-idle / transcript / summary endpoints, "Session Closer" n8n workflow (`workflows/session_closer.json`, every 10 min, Groq), retries, history block live | ✅ done 2026-10-22 (15 API tests + live: aged FR session summarized, new session recalled name/appointment/allergy) |
| 3 | `customer_profiles`, dashboard **Customers** page (profiles, sessions, transcripts, edit profile, forget customer), per-business idle-timeout field, absolute dates in summaries | ✅ done 2026-10-22 (17 API checks + live run) |

## Phase 3 additions
- **Profile:** the summarizer returns JSON (`summary`, `name`, `language`, `preferences`). Facts merge into `customer_profiles`; null/empty values never erase what is known. On a new session the agent gets `[CUSTOMER PROFILE]` (with the history block).
- **Absolute dates:** the summary prompt carries the conversation's date/weekday (business timezone) and must rewrite "tomorrow"/"Saturday" as e.g. "Saturday 2026-10-24".
- **API (admin JWT only):** `GET /customer/list/{business}`, `GET|PUT /customer/{business}/{phone}`, `DELETE /customer/{business}/{phone}` (forget: messages, sessions, profile; orders and appointments stay).
- **Dashboard:** `/customers` page; idle timeout editable on the business edit page (`session_idle_minutes`, 5–10080).

## Known limits
- Customer history appears only in the prompt of the session's first message; later turns see the current conversation (which includes the reply written with that history), not the summaries themselves.
- Current-conversation context is capped at the latest 30 messages of the session.
