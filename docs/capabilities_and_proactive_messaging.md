# WhatsApp AI Agent — Capabilities & Proactive Messaging Design

> Companion to `system_design_and_business_model.md` and `implementation_plan.md`.
> This document is the source of truth for the **full set of 9 product capabilities**, their
> implementation status, and the design of the **missing proactive (outbound) features**.

---

## 1. The 9 Capabilities

| # | Capability | Type | Status | Tool / Mechanism |
|---|---|---|---|---|
| 1 | FAQ & Inquiry | Reactive | ✅ Done | LLM via `system_prompt` (no tool) |
| 2 | Appointment Booking | Reactive | ✅ Done | `book_appointment` → `POST /appointment/create` |
| 3 | Appointment Reminders | **Proactive** | ❌ Not done | Scheduler → outbound template |
| 4 | Subscription Reminders (client's customers) | **Proactive** | ❌ Not done | New model + scheduler → outbound template |
| 5 | Order Taking | Reactive | ✅ Done | `create_order` → `POST /order/create` |
| 6 | Order Status Updates | Mixed | 🟡 Partial | ✅ `get_order_status` (pull) · ❌ push on change |
| 7 | Human Escalation | Reactive | 🟡 Partial | ✅ logs event · ❌ owner WhatsApp notify |
| 8 | After-Hours Handling | Reactive | ✅ Done | `Build Prompt` node (Beirut TZ + `opening_hours`) |
| 9 | Follow-up Messages | **Proactive** | ❌ Not done | Scheduler → outbound (free-text or template) |

**Reactive** = customer messages first, agent replies inside the open webhook loop. All built.
**Proactive** = the system initiates contact on a schedule or event. None built — all blocked on the same foundations (Section 2).

---

## 2. Why every proactive feature is blocked on the same 3 foundations

Capabilities 3, 4, 9 — plus the "push" half of 6 and the "notify" half of 7 — cannot function until these exist:

### F1 — Outbound send channel (Meta Cloud API)
The current workflow can only reply within an open HTTP webhook (`Respond to Webhook`). It cannot *initiate* a message. Requires the Meta Cloud API `POST /{phone_number_id}/messages` send path with per-business credentials. (This is Phase 4 of the implementation plan.)

### F2 — Scheduler / dispatcher
Something that wakes up on a timetable, asks the backend "what's due right now?", and triggers sends. Nothing like this exists today. Implemented as **n8n Schedule Trigger** workflows (recommended — keeps Meta logic in n8n) or a backend cron.

### F3 — WhatsApp message templates
Meta only allows business-initiated messages **outside the 24-hour customer-service window** via pre-approved templates (category `UTILITY` for reminders/updates, `MARKETING` for promos). Reminders and follow-ups almost always fall outside that window, so approved templates are **mandatory**, not optional.

```
F1 (outbound) ──┬─→ #7 escalation owner-notify (event-driven)
                └─→ + F2 (scheduler) + F3 (templates)
                        ├─→ #3 appointment reminders
                        ├─→ #4 subscription reminders
                        ├─→ #6 order-status push
                        └─→ #9 follow-up messages
```

---

## 3. Shared architecture for proactive messaging

Two new reusable building blocks serve all proactive features.

### 3.1 Outbound Send Workflow (n8n)
A dedicated n8n workflow with a **Webhook trigger** that the backend (or scheduler) calls. It:
1. Receives `{ business_id, to (customer_phone), message | template, params }`.
2. Loads the business's Meta credentials (`phone_number_id`, `access_token`).
3. Chooses **free-text** (if within 24h window) or **template** send.
4. Calls `POST https://graph.facebook.com/v18.0/{phone_number_id}/messages`.
5. Logs the outbound message via `POST /conversation/log` (role `assistant`).

### 3.2 Generic Scheduled-Message Queue (backend)
A single table that backs follow-ups and can also back reminders. The scheduler drains it.

```
scheduled_messages
------------------------------------------------------------
id              PK
business_id     FK businesses
customer_phone  string
kind            enum: appointment_reminder | subscription_reminder
                    | order_status | follow_up | escalation_alert
template_name   string (nullable — null = free-text)
payload         JSON  (template params or message text + context)
send_at         timestamp (when it becomes due)
status          enum: pending | sent | cancelled | failed
attempts        int default 0
sent_at         timestamp (nullable)
created_at      timestamp
```

### 3.3 Dispatch loop (n8n Schedule Trigger, every ~5 min)
```
[Schedule Trigger] every 5 min
      ↓
[HTTP GET] /internal/scheduled-messages/due        → list of due rows
      ↓ (split in batches)
[HTTP POST] → Outbound Send Workflow (per row)
      ↓
[HTTP POST] /internal/scheduled-messages/{id}/sent  → mark sent
```
Reminders (#3, #4) can either be **materialized** into `scheduled_messages` ahead of time, or computed live by dedicated "due" queries (Section 5). Recommended: dedicated due-queries for reminders (always reflect latest data), generic queue for follow-ups (#9).

---

## 4. New & changed data models

### 4.1 New table — `customer_subscriptions` (capability #4)
Tracks recurring services the **client** sells to **their** customers (NOT the agent's billing plans).
```
customer_subscriptions
------------------------------------------------------------
id                  PK
business_id         FK businesses
customer_phone      string
customer_name       string (nullable)
service_name        string            -- e.g. "Monthly gym membership"
amount              numeric (nullable)
period              enum: weekly | monthly | quarterly | yearly
next_due_at         date              -- next renewal/payment date
reminder_days_before int default 3
status              enum: active | paused | cancelled
last_reminded_at    timestamp (nullable)
created_at          timestamp
```

### 4.2 New table — `scheduled_messages` (capabilities #9, and optionally #3/#4/#6)
See Section 3.2.

### 4.3 Changed table — `appointments` (capability #3)
Add: `reminder_sent_at TIMESTAMP NULL` — set when the reminder fires, to prevent duplicates.

### 4.4 Changed table — `orders` (capability #6 push)
Add: `last_status_notified VARCHAR NULL` — last status value pushed to the customer, so we only notify on change.

### 4.5 Changed table — `businesses`
Add Meta credentials + reminder settings:
```
whatsapp_phone_number_id   VARCHAR   -- Meta
whatsapp_access_token      VARCHAR   -- Meta (store encrypted)
whatsapp_waba_id           VARCHAR   -- Meta
appt_reminder_hours_before INT default 24
followup_enabled           BOOLEAN default false
followup_delay_hours       INT default 24
```

### 4.6 Optional table — `message_templates`
Registry of Meta-approved templates per business (name, language, category, status, body, params). Useful once templates are submitted for approval.

---

## 5. New API endpoints

### Customer subscriptions (capability #4) — admin + agent
```
POST   /customer-subscription/create
GET    /customer-subscription/list/{business_id}
PUT    /customer-subscription/{id}
DELETE /customer-subscription/{id}
```

### Internal "due" queries (called by the scheduler only)
```
GET  /internal/due/appointment-reminders     -- appts within window, reminder_sent_at IS NULL, status active
GET  /internal/due/subscription-reminders     -- subs where next_due_at - reminder_days_before <= today, not yet reminded this cycle
GET  /internal/scheduled-messages/due         -- scheduled_messages where send_at <= now AND status = pending
POST /internal/appointment/{id}/reminded      -- set reminder_sent_at
POST /internal/customer-subscription/{id}/reminded  -- set last_reminded_at, roll next_due_at if past due
POST /internal/scheduled-messages/{id}/sent   -- set status=sent, sent_at
```
> These should be protected by a shared secret header (scheduler ↔ backend), not the admin JWT.

### Order status push hook (capability #6)
Extend the existing `PUT /order/{order_id}/status`: when status changes, enqueue a `scheduled_messages` row (`kind=order_status`, `send_at=now`) **if** `notify_customer` is true — so the dispatch loop pushes "Your order is now {status}".

### Escalation owner-notify (capability #7)
Extend the existing `POST /escalation/create`: enqueue a `scheduled_messages` row (`kind=escalation_alert`, `to=business.escalation_number`, `send_at=now`).

---

## 6. New LLM tools (n8n) vs. scheduled (non-LLM) capabilities

Most proactive features are **not** LLM tools — they fire on a schedule or event, not on
customer intent. **No new LLM tool is added.**

| Capability | Surfaced to LLM as a tool? | How data is created |
|---|---|---|
| #4 Subscription Reminders | ❌ **Owner-managed automation** | Business owner/admin enters customer subscriptions in the dashboard (Subscriptions page) or via bulk import; the **scheduler** sends renewal reminders automatically. The conversational agent is **not** involved. |
| #9 Follow-up | ⚠️ Optional (could add `schedule_follow_up`) | Event/rule-driven enqueue into `scheduled_messages`. |
| #3, #6-push, #7-notify | ❌ Scheduler/event driven | Generated by the dispatch cycle / event hooks. |

> **Design intent for #4:** the point is to relieve the business owner of manually messaging
> every customer about renewals (e.g. an internet provider with monthly subscribers). The owner
> maintains the subscriber list; the agent automates the outreach. It is therefore a
> **management automation**, not a chat tool. `POST /customer-subscription/create` is an
> admin-authenticated endpoint, gated by the `subscription_reminders` capability.
>
> *Future enhancement:* CSV bulk import of subscribers (an internet provider may have hundreds).

---

## 7. Plan → capability gating

Extend the existing tool catalog (`tools` + `plan_tools` tables, see `tool_policy.py`) with **capability entries** so each can be gated per subscription plan — even the ones that aren't `$fromAI` LLM tools:

| Tool/capability id | Display name | Suggested plan tier |
|---|---|---|
| `faq` | FAQ & Inquiry | basic+ |
| `appointments` | Appointment Booking | business+ |
| `appointment_reminders` | Appointment Reminders | business+ |
| `subscription_reminders` | Subscription Reminders | enterprise |
| `orders` | Order Taking | business+ |
| `order_status_updates` | Order Status Updates | business+ |
| `escalation` | Human Escalation | basic+ |
| `after_hours` | After-Hours Handling | basic+ |
| `follow_ups` | Follow-up Messages | enterprise |

The scheduler must check each business's `enabled_tools` before sending (e.g. only send appointment reminders if `appointment_reminders` is enabled for that business).

---

## 8. WhatsApp templates to submit for approval (Meta)

| Template name | Category | Params | Used by |
|---|---|---|---|
| `appointment_reminder` | UTILITY | name, datetime, business_name | #3 |
| `subscription_reminder` | UTILITY | name, service_name, due_date, amount | #4 |
| `order_status_update` | UTILITY | name, order_id, status | #6 |
| `escalation_alert` | UTILITY | customer_phone, last_message | #7 (to owner) |
| `follow_up_generic` | UTILITY/MARKETING | name, business_name | #9 |

---

## 9. Build order (slots into the implementation plan)

1. **Phase 4 (existing)** — Meta inbound + outbound + webhook verification → unlocks **F1** and **#7 notify**.
2. **Phase 4.5 (new) — Proactive Messaging Foundation**
   - Outbound Send Workflow (n8n) + `scheduled_messages` table + dispatch loop (n8n Schedule Trigger) → **F2**.
   - Submit Meta templates → **F3**.
3. **Phase 4.6 (new) — Proactive Capabilities**
   - #3 appointment reminders (add `reminder_sent_at`, due-query, dispatch).
   - #4 customer subscriptions (new model, CRUD, agent tool, due-query, dispatch).
   - #6 order-status push (hook on status change).
   - #9 follow-ups (enqueue rules + dispatch).
4. Add the capability entries to the tool catalog and wire plan gating into the scheduler.

> Net effect: these proactive features represent **5 of the 9 capabilities** and cannot be demoed before Phase 4. Phase 4 is therefore the unlock for the majority of the product's advertised value, not merely "make it real WhatsApp."
