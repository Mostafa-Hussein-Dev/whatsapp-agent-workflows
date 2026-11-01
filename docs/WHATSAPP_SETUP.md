# Phase 4 + Proactive Messaging — Setup & Activation Guide

This guide takes you from the code that was just added to a **live WhatsApp agent** that
also sends **reminders, follow-ups, status updates, and escalation alerts**.

There are two layers:
1. **Inbound (Phase 4)** — real customers message your WhatsApp number → agent replies.
2. **Proactive** — the scheduler sends business-initiated messages (reminders/follow-ups/etc.).

You can test the **entire pipeline locally with `WHATSAPP_DRY_RUN=true`** (no Meta account
needed — sends are logged to the API console). Then flip to real sending when ready.

---

## 0. One-time: apply the new database changes

From `agent-api/` (PostgreSQL must be running):

```powershell
cd C:\Mostafa-Files\Computer-Engineering\whatsapp-agent\agent-api
python migrate_add_tools_catalog.py   # (if not already run) base tool catalog
python migrate_add_proactive.py       # new tables + columns + capability tools
pip install -r requirements.txt       # installs httpx
```

`migrate_add_proactive.py` is idempotent. It creates `customer_subscriptions` and
`scheduled_messages`, adds the new columns, and seeds the new capability tools into the plans.

---

## 1. Configure environment

Copy the example and fill it in:

```powershell
copy .env.example .env   # if you don't have .env yet
```

Key new variables (in `agent-api/.env`):

| Variable | What it is |
|---|---|
| `META_VERIFY_TOKEN` | Any string you choose. **Must match** the n8n "Build Challenge" node. |
| `INTERNAL_API_SECRET` | Shared secret. **Must match** the `X-Internal-Secret` header in the n8n workflows. |
| `META_GRAPH_VERSION` | `v18.0` (default). |
| `META_PHONE_NUMBER_ID` / `META_ACCESS_TOKEN` | Optional global fallback creds (handy for the Meta **test number**). Per-business creds override these. |
| `WHATSAPP_DRY_RUN` | `true` = log instead of send (test locally). `false` = send for real. |

Then restart the API:

```powershell
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

> Keep `WHATSAPP_DRY_RUN=true` until you've finished testing. In dry-run, every "send"
> prints `[DRY_RUN] ...` to the uvicorn console so you can watch the pipeline work.

---

## 2. Import the n8n workflows

In n8n (http://localhost:5678):

1. **Import** `workflows/inbound.json` → the new inbound workflow.
2. **Import** `workflows/scheduler.json` → the proactive dispatcher.

In **both** imported workflows, update the placeholder secret to match your `.env`:
- `inbound.json` → node **Send WhatsApp Reply** → header `X-Internal-Secret`.
- `inbound.json` → node **Build Challenge** → `VERIFY_TOKEN` constant (must equal `META_VERIFY_TOKEN`).
- `scheduler.json` → node **Run Dispatch** → header `X-Internal-Secret`.

Re-select your **Groq** credential on the `Groq Chat Model` node (credential IDs don't transfer between machines).

Activate both workflows.

> Tip to confirm you imported the right file: the inbound workflow is named
> **"WhatsApp AI Agent - Inbound"** and contains a `Send WhatsApp Reply` node,
> a `Has Message?` IF node, and a `Webhook Verify (GET)` node — the Phase 3 workflow has none of these.

---

## 3. Test the whole thing locally (DRY_RUN, no Meta needed)

### 3a. Inbound (simulated)
The Phase 4 Parse node still accepts the simple test format, so your existing curl/test script works:

```powershell
curl -X POST http://localhost:5678/webhook/whatsapp -H "Content-Type: application/json" -d "{\"message_text\": \"What are your hours?\", \"from\": \"96170000001\", \"to\": \"<a real business number from your DB>\"}"
```
You should get the agent reply, and the uvicorn console should show a `[DRY_RUN] text -> 96170000001: ...` line from **Send WhatsApp Reply**.

### 3b. Proactive (the new part)
Trigger a dispatch manually instead of waiting for the 5-min cron:

```powershell
curl -X POST http://localhost:8000/internal/dispatch -H "X-Internal-Secret: change_me_internal_secret"
```
Response shows counts: generated reminders, sent, failed. Watch the uvicorn console for `[DRY_RUN]` sends.

**To generate something to dispatch:**
- **Order status push (#6):** in the dashboard, open an order for a business that has
  *Order Status Updates* enabled and change its status → a `scheduled_messages` row appears
  (see the **Outbox** page) → next dispatch sends it.
- **Escalation alert (#7):** trigger an escalation (agent `escalate_to_human`) for a business
  with an `escalation_number` set → an `escalation_alert` row appears → dispatched to the owner.
- **Appointment reminders (#3):** create an appointment whose time is within the business's
  `appt_reminder_hours_before` window → dispatch enqueues + sends a reminder, sets `reminder_sent_at`.
- **Subscription reminders (#4):** add a Customer Subscription with `next_due_at` within
  `reminder_days_before` → dispatch enqueues + sends, sets `last_reminded_at`.

Everything is visible in the dashboard **Outbox** page (status pending → sent).

---

## 4. Go live with real WhatsApp (Meta Cloud API)

### 4.0 What credentials you need (summary)

| # | Credential | Where in Meta | Where it goes in our system |
|---|---|---|---|
| 1 | **Phone Number ID** | WhatsApp → API Setup | Dashboard → Business → Edit → *Phone Number ID*, or `META_PHONE_NUMBER_ID` in `.env` |
| 2 | **WhatsApp Business Account ID** (WABA ID) | WhatsApp → API Setup | Dashboard → Business → Edit → *WhatsApp Business Account ID* |
| 3 | **Access Token** | WhatsApp → API Setup (temp), or System User (permanent) | Dashboard → Business → Edit → *Access Token*, or `META_ACCESS_TOKEN` in `.env` |
| 4 | **Verify Token** | ⚠️ **You invent this** — Meta does NOT give it | `META_VERIFY_TOKEN` in `.env` **and** the `VERIFY_TOKEN` constant in the n8n *Build Challenge* node (must match) |
| 5 | **Display phone number** (the actual number, e.g. `15550123456`) | WhatsApp → API Setup (under the "From" number) | Dashboard → Business → WhatsApp Numbers (used for inbound routing) |

> **#1 vs #5 are different things:** the *Phone Number ID* is an internal Meta ID used to **send**;
> the *display phone number* is the human number used to **route inbound** (matched against Meta's
> `display_phone_number`). You need **both**.
>
> **You do NOT need** the **App ID** or **App Secret** — our send path authenticates with the access token only.
>
> **Minimum to start** on Meta's free test number: **#1 Phone Number ID**, **#3 Access Token** (temp is fine), **#4 Verify Token** (you choose it).

### 4.1 Create the Meta app (click-by-click)
1. Go to https://developers.facebook.com → log in with your Facebook account.
2. Top-right → **My Apps** → **Create App**.
3. "What do you want your app to do?" → **Other** → **Next**.
4. App type → **Business** → **Next**.
5. Name it (anything) + your email → **Create app** (re-enter your FB password if prompted).
6. On the app **Dashboard**, scroll to "Add products to your app" → find **WhatsApp** → **Set up**.
7. If asked, **select or create a Meta Business Account** → **Continue**.

### 4.2 Grab the credentials (the API Setup page)
Left sidebar → **WhatsApp → API Setup**. In the **"Send and receive messages"** box:
- The **From** dropdown shows a free **test number** (e.g. `+1 555 0100`) → the number itself is your **#5 display phone number**.
- **Phone number ID** (just under it) → **#1**. Copy it.
- **WhatsApp Business Account ID** → **#2 (WABA ID)**. Copy it.
- **Temporary access token** (near the top, has a Copy button) → **#3** (valid 24h).

**Add your phone as a test recipient:** in the **To** field → **Manage phone number list** → add your
own WhatsApp number → confirm the code Meta texts you. (Lets you receive test messages; nothing to store.)

**The verify token (#4) — you make it up:** don't look for it in Meta. Decide a string now
(e.g. `change_me_verify_token`). You'll type the same value into Meta's webhook config (§4.5) and into `.env`.

#### Permanent access token (recommended before going live)
The API Setup token (#3) expires in **24h** and inbound/outbound silently stop. For a token that doesn't expire:
1. Go to https://business.facebook.com → **Business Settings** (gear icon).
2. Left menu → **Users → System Users** → **Add** → name it → role **Admin** → create.
3. Click the system user → **Add Assets** → **Apps** → select your app → toggle **Full control** → **Save**.
4. **Generate New Token** → select your app → check **`whatsapp_business_messaging`** + **`whatsapp_business_management`** → **Generate token**.
5. **Copy it immediately** (shown only once). Use this in place of #3.

### 4.3 Store the credentials in our system
Per business (recommended): Dashboard → **Businesses → Edit** → **WhatsApp Cloud API** section →
paste Phone Number ID (#1), WABA ID (#2), Access Token (#3) → Save.
Or globally for the test number: set `META_PHONE_NUMBER_ID` / `META_ACCESS_TOKEN` in `.env`.

Also map the business's **display phone number** (#5, digits only) to the business so inbound routing
works — Dashboard → Businesses → WhatsApp Numbers must match what Meta sends as `display_phone_number`.

### 4.4 Expose n8n publicly (local dev)
Meta must reach your n8n. Install ngrok and run:
```powershell
ngrok http 5678
```
You get a URL like `https://abc123.ngrok-free.app`.

### 4.5 Configure the webhook in Meta
In **WhatsApp → Configuration → Webhook**:
- **Callback URL:** `https://abc123.ngrok-free.app/webhook/whatsapp`
- **Verify token:** the exact value of `META_VERIFY_TOKEN`.
- Click **Verify and save** — Meta sends a GET; the workflow's **Webhook Verify (GET) → Build Challenge → Respond Verify** chain answers it.
- **Subscribe** to the **messages** field.

> Alternative: point the Callback URL at the backend instead
> (`https://.../whatsapp/webhook`) which has a built-in verify endpoint — but inbound message
> *processing* must still go to n8n (that's where the LLM runs), so keep the webhook on n8n.

### 4.6 Submit message templates (required for proactive sends)
Business-initiated messages outside the 24h window need **approved templates**. In
**WhatsApp → Message Templates**, create these (category **UTILITY**), with body variables in order:

| Template name | Body (example) | Variables |
|---|---|---|
| `appointment_reminder` | "Hi {{1}}, reminder: your appointment is on {{2}} with {{3}}." | name, datetime, business |
| `subscription_reminder` | "Hi {{1}}, your {{2}} renews on {{3}} {{4}}." | name, service, date, amount |
| `order_status_update` | "Hi {{1}}, your order #{{2}} is now {{3}}." | name, order_id, status |
| `escalation_alert` | "A customer {{1}} needs attention: {{2}}" | customer_phone, last_message |
| `follow_up_generic` | "Hi {{1}}, thanks for choosing {{2}}! How did we do?" | name, business |

The template **names** must match exactly — `whatsapp_client.send_scheduled()` uses them.
(Inside the 24h window the reply path uses free text, no template needed.)

### 4.7 Flip to real sending
In `.env` set `WHATSAPP_DRY_RUN=false` and restart the API.

### 4.8 End-to-end test
- Message your Meta test number from your phone → you get an AI reply within seconds.
- Change an order status / create a due reminder → within 5 minutes (or via manual dispatch)
  the customer receives the proactive message.

---

## 5. How the pieces connect

```
Inbound:
  Customer → Meta → (ngrok) → n8n Webhook (POST /webhook/whatsapp)
    → Parse → Has Message? → Get Business ID → Load Config → Build Prompt
    → AI Agent (+ tools: book_appointment, create_order, get_order_status,
                 escalate_to_human)
    → Log User → Log Assistant → Send WhatsApp Reply (POST /whatsapp/send) → 200

Proactive:
  n8n Schedule Trigger (every 5 min) → POST /internal/dispatch (X-Internal-Secret)
    → generate appointment + subscription reminders
    → roll past-due subscriptions
    → send all due scheduled_messages via Meta
  (order-status & escalation rows are enqueued at event time by the API)
```

---

## 6. Troubleshooting

| Symptom | Fix |
|---|---|
| Webhook "Verify and save" fails | `META_VERIFY_TOKEN` (.env) ≠ `VERIFY_TOKEN` in the **Build Challenge** node. |
| `/internal/dispatch` returns 401 | `INTERNAL_API_SECRET` (.env) ≠ `X-Internal-Secret` header in n8n. |
| Reminders never send | Business missing the capability (`appointment_reminders` / `subscription_reminders`) in **Enabled Tools**, or item is outside the reminder window. |
| Outbox rows stuck `pending` | Scheduler workflow not active, or `/internal/dispatch` not reachable from n8n (use `host.docker.internal`). |
| Sends fail with Meta 400 | Outside 24h window without an approved template, or wrong template name/params, or expired access token. |
| Inbound does nothing | The WhatsApp `display_phone_number` from Meta isn't mapped to a business; check Get Business ID. |
| Customer gets no reply but logs show output | `WHATSAPP_DRY_RUN=true` (still in test mode) or missing per-business Meta creds. |
```
