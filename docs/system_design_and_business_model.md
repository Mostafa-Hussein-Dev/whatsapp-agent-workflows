# WhatsApp AI Agent — Full System Design & Business Model
### Lebanese SMB Market | Solo Developer Product

---

## 1. Product Summary

A multi-tenant WhatsApp AI Agent platform sold as a subscription service to Lebanese small and medium businesses. Each business gets an AI agent running on their WhatsApp number that handles customer inquiries, bookings, orders, and escalations — autonomously, 24/7.

---

## 2. System Architecture

### 2.1 High-Level Overview

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENT SIDE                          │
│         WhatsApp User ↔ Business WhatsApp Number        │
└─────────────────────────┬───────────────────────────────┘
                          │ webhook
┌─────────────────────────▼───────────────────────────────┐
│                   YOUR INFRASTRUCTURE                   │
│                                                         │
│   ┌─────────────────────────────────────────────────┐   │
│   │              n8n (Orchestration Layer)          │   │
│   │                                                 │   │
│   │  Webhook → Extract business_id                  │   │
│   │       → Load config (MCP call)                  │   │
│   │       → AI Agent Node (LLM + tools)             │   │
│   │       → Reply to WhatsApp                       │   │
│   └──────────────────┬──────────────────────────────┘   │
│                      │ MCP / HTTP                        │
│   ┌──────────────────▼──────────────────────────────┐   │
│   │           FastAPI MCP Server                    │   │
│   │                                                 │   │
│   │  /client/config     → load business config      │   │
│   │  /conversation/log  → save message history      │   │
│   │  /order/create      → create new order          │   │
│   │  /order/get         → fetch order status        │   │
│   └──────────────────┬──────────────────────────────┘   │
│                      │                                   │
│   ┌──────────────────▼──────────────────────────────┐   │
│   │  PostgreSQL          │  Redis                   │   │
│   │  (persistent data)   │  (conversation memory)   │   │
│   └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Component Breakdown

#### n8n — Orchestration Layer
Handles the full agent loop visually. One master workflow serves all clients dynamically.

Responsibilities:
- Receive WhatsApp webhook from Meta
- Extract `business_id` from the incoming phone number mapping
- Call FastAPI MCP to load client config
- Run AI Agent node with the client's system prompt and tools
- Call native n8n tool nodes (Google Calendar, email, WhatsApp reply)
- Call FastAPI MCP for any DB reads/writes
- Send reply back to user via Meta Cloud API

#### FastAPI MCP Server — Business Logic & Data Layer
A lightweight Python API that acts as the MCP server for the agent. Handles only what n8n cannot natively do.

Responsibilities:
- Load client config (system prompt, enabled tools, escalation contacts)
- Store and retrieve conversation history
- CRUD for orders, appointments, customer records
- Phone number → business_id mapping

#### PostgreSQL — Persistent Storage
Stores all business and operational data.

Key tables:
- `businesses` — client configs, subscription status, system prompts
- `whatsapp_numbers` — maps phone numbers to business_id
- `conversations` — full message logs per session
- `orders` — order records per business
- `appointments` — booking records per business

#### Redis — Conversation Memory
Stores short-term conversation context per WhatsApp session (phone number as key). Expires after inactivity (e.g. 2 hours). Prevents the agent from losing context mid-conversation.

#### Meta Cloud API — WhatsApp Gateway
Free WhatsApp Business API. Receives incoming messages via webhook (POST to your n8n) and sends outgoing messages via HTTP.

---

## 3. Detailed Agent Flow

```
1. User sends WhatsApp message to business number
        ↓
2. Meta sends webhook POST → n8n endpoint
        ↓
3. n8n extracts: user_phone, business_number, message_text
        ↓
4. n8n maps business_number → business_id (via FastAPI MCP)
        ↓
5. n8n loads from Redis: conversation history for this user
        ↓
6. n8n calls FastAPI MCP: get_client_config(business_id)
   Returns: system_prompt, enabled_tools, escalation_number, business_name
        ↓
7. n8n AI Agent node:
   - System prompt = client config
   - Context = conversation history from Redis
   - Available tools = based on enabled_tools flag
        ↓
8. LLM decides:
   a) Reply directly → go to step 11
   b) Call a tool → go to step 9
        ↓
9. Tool execution:
   - Google Calendar → native n8n node
   - Send email → native n8n node
   - Create/get order → FastAPI MCP
   - Escalate to human → WhatsApp forward via n8n
        ↓
10. Tool result fed back to LLM → loop back to step 8
        ↓
11. Final reply generated
        ↓
12. n8n saves message + reply to Redis (context) and PostgreSQL (log)
        ↓
13. n8n sends reply via Meta Cloud API → User receives message
```

---

## 4. Database Schema

```sql
-- Core business table
CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    industry VARCHAR(100),
    system_prompt TEXT NOT NULL,
    enabled_tools JSONB DEFAULT '[]',
    escalation_number VARCHAR(20),
    subscription_plan VARCHAR(50),
    subscription_status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT NOW()
);

-- WhatsApp number to business mapping
CREATE TABLE whatsapp_numbers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID REFERENCES businesses(id),
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    display_name VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE
);

-- Conversation logs
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID REFERENCES businesses(id),
    customer_phone VARCHAR(20) NOT NULL,
    role VARCHAR(10) NOT NULL, -- 'user' or 'assistant'
    message TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Orders
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID REFERENCES businesses(id),
    customer_phone VARCHAR(20),
    customer_name VARCHAR(255),
    items JSONB,
    status VARCHAR(50) DEFAULT 'pending',
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Appointments
CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID REFERENCES businesses(id),
    customer_phone VARCHAR(20),
    customer_name VARCHAR(255),
    scheduled_at TIMESTAMP,
    status VARCHAR(50) DEFAULT 'confirmed',
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## 5. FastAPI MCP Server — Endpoints

```
GET  /client/config/{business_id}         → returns full client config
GET  /client/by-phone/{phone_number}      → returns business_id from phone

POST /conversation/log                    → saves message to DB
GET  /conversation/history/{business_id}/{customer_phone} → returns last N messages

POST /order/create                        → creates new order
GET  /order/{order_id}                    → fetches order status
PUT  /order/{order_id}/status             → updates order status

POST /appointment/create                  → creates appointment
GET  /appointment/{business_id}/upcoming  → lists upcoming appointments
```

---

## 6. n8n Workflow Design

### Master Workflow (Single workflow for all clients)

```
[Webhook Trigger]
      ↓
[Function Node] — parse Meta webhook payload, extract phone numbers
      ↓
[HTTP Request] → FastAPI /client/by-phone/{business_number}
      ↓
[HTTP Request] → FastAPI /client/config/{business_id}
      ↓
[HTTP Request] → FastAPI /conversation/history (load last 10 messages)
      ↓
[AI Agent Node]
  - Model: Groq / Claude / DeepSeek (swappable)
  - System prompt: from client config
  - Tools:
      • Google Calendar (native)
      • Send Email (native)
      • HTTP Request → FastAPI /order/create
      • HTTP Request → FastAPI /appointment/create
      • HTTP Request → FastAPI /order/{id}
      ↓
[HTTP Request] → FastAPI /conversation/log (save exchange)
      ↓
[HTTP Request] → Meta Cloud API (send reply to user)
```

---

## 7. Infrastructure & Hosting

### VPS Setup (Hetzner — recommended)

| Service | Spec | Cost |
|---|---|---|
| Hetzner CX22 VPS | 2 vCPU, 4GB RAM | €4/month |
| Domain | yourproduct.com | ~$10/year |
| SSL | Let's Encrypt (Certbot) | Free |
| Total | | ~$5–6/month |

### Docker Compose Stack on VPS

```yaml
version: "3.8"
services:

  n8n:
    image: n8nio/n8n
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=n8n.yourproduct.com
      - WEBHOOK_URL=https://n8n.yourproduct.com
    volumes:
      - n8n_data:/home/node/.n8n
    restart: unless-stopped

  fastapi:
    build: ./api
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres:5432/agentdb
      - REDIS_URL=redis://redis:6379
    restart: unless-stopped

  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=agentdb
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - certbot_data:/etc/letsencrypt
    restart: unless-stopped

volumes:
  n8n_data:
  postgres_data:
  certbot_data:
```

---

## 8. Business Model

### 8.1 Target Market

Lebanese SMBs that:
- Rely heavily on WhatsApp for customer communication
- Have repetitive, high-volume message handling
- Cannot afford a full support team or CRM
- Operate in: clinics, restaurants, retail, real estate, catering, pharmacies

### 8.2 Pricing Plans

| Plan | Price (USD/month) | What's included |
|---|---|---|
| **Starter** | $29 | 1 WhatsApp number, FAQ handling, escalation, 500 conversations/month |
| **Business** | $59 | 1 WhatsApp number, all tools (booking, orders, follow-ups), 2000 conversations/month |
| **Pro** | $99 | 2 WhatsApp numbers, all tools, unlimited conversations, priority support |

Note: Lebanese businesses prefer USD over LBP. OMT/Whish/bank transfer for payment.

### 8.3 Unit Economics

| Item | Cost |
|---|---|
| VPS (serves all clients) | ~$6/month |
| LLM API (Groq free tier to start) | $0 during testing |
| LLM API at scale (DeepSeek V3) | ~$0.001 per conversation |
| Domain + misc | ~$2/month |
| **Total infra at 20 clients** | ~$10–15/month |

At 10 clients on Starter plan:
- Revenue: $290/month
- Infra cost: ~$10/month
- **Margin: ~96%**

### 8.4 Go-To-Market Strategy

**Phase 1 — Manual outreach (Month 1–2)**
- Pick one vertical (clinics or restaurants — highest WhatsApp pain)
- DM 50 businesses on Instagram/WhatsApp directly
- Offer first month free, no contract
- Goal: 3–5 paying clients

**Phase 2 — Referral loop (Month 3–4)**
- Ask happy clients for referrals (offer 1 free month per referral)
- Lebanese SMB market is relationship-driven — word of mouth is powerful
- Goal: 10–15 clients

**Phase 3 — Content + proof (Month 5+)**
- Post case studies on LinkedIn/Instagram showing before/after (response time, missed messages)
- Offer a live demo via WhatsApp — let prospects talk to a demo agent
- Goal: 25+ clients

### 8.5 Sales Pitch (One Liner)

> "Your WhatsApp is leaking customers. We fix that for $29/month."

### 8.6 Onboarding Process (Per New Client)

1. Client fills a simple form: business name, products/services, FAQs, escalation number
2. You generate their system prompt from the form
3. Connect their WhatsApp Business number to Meta Cloud API
4. Insert their config row into PostgreSQL
5. Agent is live — no code changes needed

Target onboarding time: under 2 hours per client.

---

## 9. Competitive Advantage

| Factor | You | Generic SaaS competitors |
|---|---|---|
| Lebanon-specific | ✅ Arabic/French/English | ❌ English only |
| WhatsApp-native | ✅ Core channel | ⚠️ Add-on |
| Price | $29–99/month | $200–500/month |
| Local support | ✅ Same timezone, same market | ❌ |
| Customization | ✅ Per-business system prompt | ❌ One-size-fits-all |

---

## 10. Build Roadmap

### Month 1 — Core MVP
- n8n running locally, then on VPS
- FastAPI MCP server with basic endpoints
- PostgreSQL schema deployed
- Meta Cloud API connected
- One working workflow: receive message → LLM reply → send back
- One real client onboarded (free)

### Month 2 — Tools + Multi-tenant
- Dynamic client config loading
- Redis conversation memory
- Google Calendar integration (bookings)
- Order creation tool
- Escalation to human
- Second and third clients onboarded

### Month 3 — Productize
- Simple admin dashboard (Next.js) for you to manage clients
- Automated onboarding form
- Basic analytics per client (messages handled, escalations)
- Start charging

### Month 4+ — Scale
- Client self-service portal (edit FAQs, view logs)
- Stripe/OMT payment integration
- Expand to second vertical

---

## 11. Capabilities Matrix (Addendum)

The agent provides **9 capabilities**, split into **reactive** (customer-initiated, handled inside
the webhook reply loop) and **proactive** (system-initiated, requiring outbound + a scheduler).
Full design for the proactive features lives in `capabilities_and_proactive_messaging.md`.

| # | Capability | Type | Mechanism |
|---|---|---|---|
| 1 | FAQ & Inquiry | Reactive | LLM via system_prompt |
| 2 | Appointment Booking | Reactive | `book_appointment` tool |
| 3 | Appointment Reminders | Proactive | scheduler → outbound template |
| 4 | Subscription Reminders (client's customers) | Proactive | `customer_subscriptions` model + scheduler |
| 5 | Order Taking | Reactive | `create_order` tool |
| 6 | Order Status Updates | Reactive (pull) + Proactive (push) | `get_order_status` + status-change push |
| 7 | Human Escalation | Reactive (+ proactive owner-notify) | `escalate_to_human` + owner WhatsApp alert |
| 8 | After-Hours Handling | Reactive | Build Prompt node (Beirut TZ + opening_hours) |
| 9 | Follow-up Messages | Proactive | `scheduled_messages` queue + scheduler |

### 11.1 Additional database tables (proactive)

```sql
-- Client's own recurring services sold to their customers (capability #4)
CREATE TABLE customer_subscriptions (
    id SERIAL PRIMARY KEY,
    business_id UUID REFERENCES businesses(id),
    customer_phone VARCHAR(20) NOT NULL,
    customer_name VARCHAR(255),
    service_name VARCHAR(255) NOT NULL,
    amount NUMERIC,
    period VARCHAR(20) NOT NULL,            -- weekly|monthly|quarterly|yearly
    next_due_at DATE NOT NULL,
    reminder_days_before INT DEFAULT 3,
    status VARCHAR(20) DEFAULT 'active',     -- active|paused|cancelled
    last_reminded_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Generic outbound queue backing follow-ups, reminders, status pushes, alerts (#3,#4,#6,#7,#9)
CREATE TABLE scheduled_messages (
    id SERIAL PRIMARY KEY,
    business_id UUID REFERENCES businesses(id),
    customer_phone VARCHAR(20) NOT NULL,
    kind VARCHAR(40) NOT NULL,               -- appointment_reminder|subscription_reminder|order_status|follow_up|escalation_alert
    template_name VARCHAR(255),              -- NULL = free text
    payload JSONB,
    send_at TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',    -- pending|sent|cancelled|failed
    attempts INT DEFAULT 0,
    sent_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Column additions
ALTER TABLE appointments ADD COLUMN reminder_sent_at TIMESTAMP;       -- #3
ALTER TABLE orders       ADD COLUMN last_status_notified VARCHAR(50); -- #6 push
ALTER TABLE businesses   ADD COLUMN whatsapp_phone_number_id VARCHAR(64);  -- Meta
ALTER TABLE businesses   ADD COLUMN whatsapp_access_token VARCHAR(512);    -- Meta (encrypt)
ALTER TABLE businesses   ADD COLUMN whatsapp_waba_id VARCHAR(64);          -- Meta
ALTER TABLE businesses   ADD COLUMN appt_reminder_hours_before INT DEFAULT 24;
ALTER TABLE businesses   ADD COLUMN followup_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE businesses   ADD COLUMN followup_delay_hours INT DEFAULT 24;
```

### 11.2 Additional endpoints (proactive)

```
POST/GET/PUT/DELETE /customer-subscription/...     → CRUD client customer subscriptions (#4)

GET  /internal/due/appointment-reminders           → scheduler: due appointment reminders (#3)
GET  /internal/due/subscription-reminders          → scheduler: due subscription reminders (#4)
GET  /internal/scheduled-messages/due              → scheduler: due queued messages (#6,#7,#9)
POST /internal/appointment/{id}/reminded           → mark reminded
POST /internal/customer-subscription/{id}/reminded → mark reminded, roll next_due_at
POST /internal/scheduled-messages/{id}/sent        → mark sent
```
(Internal endpoints use a shared-secret header, not the admin JWT.)

### 11.3 Three foundations the proactive features depend on
- **Outbound send** via Meta Cloud API (Phase 4) — the system cannot currently initiate messages.
- **Scheduler** (n8n Schedule Trigger workflow) — does not exist yet.
- **Approved WhatsApp templates** — required by Meta for any message outside the 24h window.
