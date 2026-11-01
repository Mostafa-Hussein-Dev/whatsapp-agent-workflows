# AI Agent Tech Stack Comparison
## Lebanese SMB WhatsApp AI Agent — Backend Options

---

## Overview

You are building a multi-tenant WhatsApp AI agent sold as a subscription service to Lebanese small and medium businesses. The agent must:

- Receive WhatsApp messages via webhook
- Run an LLM (Claude API) to decide what to do
- Execute tools (calendar, DB lookup, order creation, escalation)
- Reply back to the user
- Serve multiple clients from one deployment

---

## Options Compared

| Criteria | n8n | Flowise | Python FastAPI | Node.js (Express/Fastify) |
|---|---|---|---|---|
| **Speed to MVP** | ⭐⭐⭐⭐⭐ Fastest | ⭐⭐⭐⭐⭐ Fastest | ⭐⭐⭐ Medium | ⭐⭐⭐ Medium |
| **True Agent (tool-use loop)** | ✅ Built-in AI Agent node | ✅ Built-in, AI-native | ✅ Manual but full control | ✅ Manual but full control |
| **Multi-tenant support** | ⚠️ Requires workflow design | ⚠️ Requires design | ✅ Native via code | ✅ Native via code | 
| **Code required** | Minimal | Minimal | Heavy | Heavy | 
| **Flexibility** | Medium | Medium | Full | Full | 
| **Self-hostable** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | 
| **Monthly infra cost** | ~$5–10 | ~$5–10 | ~$5–10 | ~$5–10 | 
| **Long-term scalability** | Medium | Medium | High | High | 
| **Debugging ease** | ✅ Visual UI | ✅ Visual UI | ⚠️ Logs only | ⚠️ Logs only | 
| **Learning curve** | Low | Low | Medium (you know it) | Medium |

---

## Option 1 — n8n (Recommended for MVP)

### What it is
A self-hosted visual workflow automation tool with a native AI Agent node. You build your agent logic by connecting nodes in a UI — no boilerplate webhook code, no manual tool routing.

### Architecture
```
WhatsApp Webhook
      ↓
n8n Webhook Node
      ↓
AI Agent Node (Claude + tools defined as sub-nodes)
      ↓
Tool Nodes: PostgreSQL / Google Calendar / HTTP Request / Send Email
      ↓
WhatsApp Reply Node (HTTP Request to Meta API)
```

### Pros
- Fastest path to a working agent — days not weeks
- Native AI Agent node handles the tool-use loop automatically
- Built-in nodes for WhatsApp, Claude, PostgreSQL, Google Calendar, HTTP
- Visual UI makes debugging and iterating easy
- One instance, multiple workflows = multi-tenant by design
- No webhook boilerplate to write

### Cons
- Less flexible than code — complex custom logic is harder
- Not a "real codebase" — harder to version control properly
- n8n itself is a dependency — if it breaks, everything breaks
- Selling a product built on n8n feels less proprietary
- Scaling beyond ~50 concurrent workflows needs a bigger VPS

### Best for
Validating the idea fast, getting first paying clients, proving the model before investing in custom code.

---

## Option 2 — Flowise

### What it is
A self-hosted, open-source visual builder specifically designed for LLM agent workflows. Built on LangChain under the hood. More AI-native than n8n — every node is an AI concept (agent, tool, memory, chain, retriever) rather than a generic automation node.

### Architecture
```
WhatsApp Webhook
      ↓
Flowise API endpoint (built-in)
      ↓
Agent Flow (Claude + tools configured visually)
      ↓
Tool Nodes: API calls, DB queries, calendar, custom functions
      ↓
Reply via HTTP back to WhatsApp API
```

### Pros
- Purpose-built for AI agents — more intuitive than n8n for this use case
- Native support for Claude, GPT, Gemini, Ollama — model-agnostic
- Built-in memory types (buffer, summary, vector store)
- Built-in RAG support — useful if clients want agent to know their product catalog/docs
- REST API exposed per flow — easy to integrate with anything
- Visual debugging with token-level visibility
- Self-hostable via Docker — same cost as n8n (~$5–10/month)
- Active community, fast-moving

### Cons
- Less mature than n8n for general automation (non-AI workflows)
- Multi-tenant isolation requires careful flow/API key design
- Fewer non-AI integrations compared to n8n (no native WhatsApp node — use HTTP)
- LangChain dependency underneath — abstractions can be leaky for complex cases
- Smaller community than n8n

### Best for
MVP phase if your agent needs RAG (client product docs, FAQs as knowledge base) or if you want a more AI-native visual tool than n8n. Strong alternative to n8n for this specific use case.

---

## Option 3 — Python FastAPI

### What it is
A custom Python backend you write from scratch. You handle webhook receiving, conversation state, LLM calls, tool execution, and reply sending in code.

### Architecture
```
WhatsApp Webhook
      ↓
FastAPI endpoint (/webhook)
      ↓
Load conversation from Redis
      ↓
Build prompt + tools → Claude API (tool_use mode)
      ↓
Execute tool if requested → DB / Calendar / etc.
      ↓
Feed result back to Claude → get final reply
      ↓
Send reply via Meta WhatsApp API
      ↓
Save conversation to Redis / log to PostgreSQL
```

### Pros
- You already know Python + FastAPI (from FYP)
- Full control over every behavior
- Clean multi-tenant architecture by design
- Easiest to extend with complex business logic
- Proper codebase — Git versioned, testable, deployable on any infra
- Best long-term foundation if this becomes a real product

### Cons
- More boilerplate to write upfront
- Tool-use loop must be implemented manually
- No visual debugging — logs only
- Slower to MVP compared to n8n
- More moving parts to manage (Redis, Postgres, FastAPI, Celery if needed)

### Best for
After validation. When you have paying clients and want to build a proper, scalable product you fully own.

---

## Option 4 — Node.js (Express or Fastify)

### What it is
Same concept as FastAPI but in JavaScript/TypeScript. Webhook handler, LLM calls, tool-use loop — all in Node.

### Architecture
Same as FastAPI — replace Python with Node.js.

### Pros
- JavaScript runs everywhere — same language as any frontend dashboard you build
- Fastify is extremely fast
- Rich npm ecosystem for WhatsApp, AI, and API integrations
- TypeScript adds safety for a growing codebase

### Cons
- Async callback patterns can get messy for complex agent loops
- You would need to learn it if Python is your primary language
- No meaningful advantage over FastAPI for this use case
- Tool-use loop still manual

### Best for
If you prefer JavaScript or already have a Node background. Otherwise FastAPI is better given your existing skills.

---

## Recommended Path

### Phase 1 — Validate (Month 1–2)
**Use n8n**

Get the agent working on n8n. Connect it to WhatsApp, wire up Claude, add 2–3 tools (booking, FAQ lookup, escalation). Onboard 3–5 paying clients. Charge $30–50/month. Prove people will pay.

### Phase 2 — Productize (Month 3–6)
**Migrate core to Python FastAPI**

Once you have revenue and know exactly what clients need, rebuild the agent engine in FastAPI. Keep n8n for non-critical automations if useful. Add a proper dashboard, billing, and onboarding flow.

### Phase 3 — Scale
**FastAPI + proper infra**

Add a job queue (Celery + Redis), proper logging, monitoring, and a client self-service portal.

---

## Final Stack Recommendation (Phase 1)

| Layer | Tool |
|---|---|
| Agent runtime | n8n (self-hosted) |
| LLM | Claude API (claude-sonnet-4) |
| WhatsApp | Meta Cloud API (free) |
| Database | PostgreSQL (client configs, logs) |
| Memory | Redis (conversation context) |
| Hosting | Hetzner VPS (~€4/month) |
| Reverse proxy | Nginx + Certbot (free SSL) |
| Dashboard | Simple Next.js admin (later) |

**Total infra cost: ~$10–15/month to serve all clients.**
