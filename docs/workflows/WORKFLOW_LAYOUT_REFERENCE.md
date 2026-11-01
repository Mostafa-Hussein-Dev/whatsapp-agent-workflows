# Phase 1 Workflow - Visual Layout Reference

## How Your Workflow Should Look in n8n

After importing the JSON file and making the manual connections, your workflow canvas should look like this:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           n8n Workflow Canvas                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────┐     ┌──────────────┐     ┌──────────┐     ┌──────────────┐  │
│   │          │     │              │     │          │     │              │  │
│   │  Webhook │────▶│   Parse      │────▶│   Set    │────▶│   AI Agent   │  │
│   │          │     │   Payload    │     │ Session  │     │              │  │
│   └──────────┘     └──────────────┘     └──────────┘     └──────┬───────┘  │
│                                                              │             │
│                                                              │      ┌──────┴───────┐
│                                                              │      │              │
│                                                              ▼      ▼              │
│                                                       ┌──────────────┐  ┌──────────────┐
│                                                       │              │  │              │
│                                                       │  Groq Model  │  │Window Memory │
│                                                       │              │  │              │
│                                                       └──────────────┘  └──────────────┘
│                                                              │             │
│                                                              └──────┬──────┘
│                                                                     │
│                                                                     ▼
│                                                              ┌──────────────┐
│                                                              │              │
│                                                              │   Respond    │
│                                                              │   to Webhook │
│                                                              │              │
│                                                              └──────────────┘
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Connection Types Explained

### 1. Main Flow Connections (solid lines)
These connect nodes sequentially in the workflow:
- Webhook → Parse Payload → Set Session ID → AI Agent → Respond to Webhook

**To create:** Drag from the right side of one node to the left side of the next node.

### 2. AI Agent Sub-Node Connections (dashed/colored lines)
These connect the AI Agent to its supporting nodes:

| From Node | To Node | Connection Type | Purpose |
|-----------|---------|-----------------|---------|
| AI Agent | Groq Model | Language Model | Provides the LLM for generating responses |
| AI Agent | Window Memory | Memory | Stores conversation context per session |

**To create:**
1. Click and hold on the **AI Agent** node
2. Drag to the **Groq Model** node
3. Select **"Language Model"** from the popup menu
4. Repeat for **Window Memory**, selecting **"Memory"**

## Node Configuration Quick Reference

| Node | Key Settings |
|------|--------------|
| **Webhook** | Path: `whatsapp`, Method: POST, Response Mode: responseNode |
| **Parse Payload** | JavaScript code extracts: `message_text`, `user_phone`, `business_number` |
| **Set Session ID** | Sets `user_phone` value for memory session tracking |
| **AI Agent** | System Message (see below), Prompt: `={{ $json.message_text }}` |
| **Groq Model** | Model: `llama-3.3-70b-versatile`, Temp: `0.3`, Max Tokens: `500` |
| **Window Memory** | Window Size: `10`, Session ID: `={{ $json.user_phone }}` |
| **Respond to Webhook** | Response Body: `={{ $json.text }}`, Response Code: `200` |

## AI Agent System Message

Copy and paste this into the AI Agent's System Message field:

```
You are a helpful assistant for a Lebanese business. Reply in the same language the customer uses (Arabic, French, or English). Be concise, friendly, and professional. If you do not know the answer, say so and offer to connect the customer with a human.
```

## Troubleshooting Connections

### Problem: Can't connect AI Agent to Groq Model
- **Solution:** Make sure you're dragging FROM the AI Agent TO the Groq Model, not the other way around

### Problem: Connection type option doesn't appear
- **Solution:** Zoom in on the nodes and try again - sometimes the popup is off-screen

### Problem: "Language Model" option not available
- **Solution:** Make sure the Groq Model node is the correct type (`@n8n/n8n-nodes-langchain.groqChat`)

### Problem: Window Memory not remembering conversations
- **Solution:** Verify Session ID is set to `={{ $json.user_phone }}` exactly

## Verification Checklist

Before testing, verify:

- [ ] Webhook node shows the webhook URL (after activation)
- [ ] Main flow: Webhook → Parse → Set → AI Agent → Respond (all connected)
- [ ] AI Agent → Groq Model (Language Model connection)
- [ ] AI Agent → Window Memory (Memory connection)
- [ ] Groq Model has API credential configured
- [ ] AI Agent has system message set
- [ ] Window Memory has Session ID set to user_phone
- [ ] Workflow is activated (toggle is ON)

## Test Command

Once verified, test with:

```bash
curl -X POST http://localhost:5678/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{"message_text": "Hello, what are your opening hours?", "from": "96170000001", "to": "96171000002"}'
```

Expected response (example):
```json
{"text": "Hello! Our business hours are Monday to Saturday, 9am to 6pm. How can I help you today?"}
```
