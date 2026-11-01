# Phase 1 Setup Guide - Core Workflow (Local)

## Overview

This guide will walk you through setting up the Phase 1 n8n workflow. This is a **local-only** workflow that receives a message, processes it through an LLM, and returns a reply.

## Prerequisites

1. **n8n installed locally** - Running at http://localhost:5678
2. **Groq API Key** - Sign up at [console.groq.com](https://console.groq.com) and get your API key

## Workflow Structure

```
Webhook → Parse Payload (Code) → AI Agent → Respond to Webhook
                                        ↓
                                  Groq Chat Model
```

---

## Step 1: Add Webhook Node

1. Click **+** to add a node
2. Search for **"Webhook"**
3. Configure:
   - **HTTP Method**: POST
   - **Path**: `whatsapp`
   - **Response Mode**: Using 'Respond to Webhook' Node
   - **Authentication**: None

---

## Step 2: Add Code Node (Parse Payload)

1. Click **+** after Webhook node
2. Search for **"Code"**
3. Rename it to **"Parse Payload"**
4. Paste this code:

```javascript
// Parse Incoming Payload
const body = $input.first().json;

return {
  json: {
    message_text: body.message_text || body.message || '',
    user_phone: body.from || body.user_phone || 'unknown',
    business_number: body.to || body.business_number || 'unknown',
    timestamp: new Date().toISOString()
  }
};
```

---

## Step 3: Add AI Agent Node

1. Click **+** after Parse Payload node
2. Search for **"AI Agent"**
3. Configure:
   - **Prompt Type**: Define
   - **Prompt**: `={{ $json.message_text }}`
   - **System Message**:

```
You are a helpful assistant for a Lebanese business. Reply in the same language the customer uses (Arabic, French, or English). Be concise, friendly, and professional. If you do not know the answer, say so and offer to connect the customer with a human.
```

---

## Step 4: Add Groq Chat Model Node

1. Click the canvas (not in the flow path)
2. Search for **"Groq"** → select **"Groq Chat Model"**
3. Configure:
   - **Model**: `llama-3.3-70b-versatile`
   - **Temperature**: `0.3`
   - **Max Tokens**: `500`
4. **Add Credential**:
   - Click "Create New Credential"
   - Select "Groq API"
   - Paste your API key from console.groq.com
   - Save

---

## Step 5: Connect AI Agent to Groq Model

1. Drag from **AI Agent** to **Groq Chat Model**
2. In the popup, select **"Language Model"**

---

## Step 6: Add Respond to Webhook Node

1. Click **+** after AI Agent node
2. Search for **"Respond to Webhook"**
3. Configure:
   - **Respond With**: JSON
   - **Response Body**: `={{ $json.text }}`
   - **Response Code**: `200`

---

## Step 7: Verify All Connections

Your workflow should look like this:

```
Webhook → Parse Payload → AI Agent → Respond to Webhook
                                   ↓
                             Groq Chat Model
```

---

## Step 8: Activate the Workflow

1. Click the **"Inactive"** toggle (top right)
2. It should change to **"Active"**
3. Copy the **Webhook URL** from the Webhook node
   - Format: `http://localhost:5678/webhook/whatsapp`

---

## Step 9: Test the Workflow

### Using curl (Bash/Terminal):

```bash
curl -X POST http://localhost:5678/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{"message_text": "Hello, what are your opening hours?", "from": "96170000001", "to": "96171000002"}'
```

### Using PowerShell:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:5678/webhook/whatsapp" -ContentType "application/json" -Body '{"message_text": "Hello, what are your opening hours?", "from": "96170000001", "to": "96171000002"}'
```

### Expected Response:

You should get a JSON reply like:
```json
{"text": "Hello! Our business hours are Monday to Saturday from 9am to 6pm. How can I help you today?"}
```

---

## Step 10: Test Different Languages

**Arabic:**
```bash
curl -X POST http://localhost:5678/webhook/whatsapp -H "Content-Type: application/json" -d '{"message_text": "هل لديكم توصيل للمنازل؟", "from": "96170000002", "to": "96171000002"}'
```

**French:**
```bash
curl -X POST http://localhost:5678/webhook/whatsapp -H "Content-Type: application/json" -d '{"message_text": "Est-ce que vous offrez la livraison à domicile?", "from": "96170000003", "to": "96171000002"}'
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Credential not found" | Create Groq API credential in Groq Chat Model node |
| "Webhook not found" | Make sure workflow is Active |
| No response from AI | Check n8n execution logs for errors |
| Wrong response format | Verify Respond to Webhook has `={{ $json.text }}` |

---

## Phase 1 Completion Checklist

- [ ] Webhook node configured (path: whatsapp, method: POST)
- [ ] Parse Payload code node with JavaScript code
- [ ] AI Agent node with system message and prompt
- [ ] Groq Chat Model node with API credential
- [ ] AI Agent connected to Groq Chat Model (Language Model)
- [ ] Respond to Webhook node configured
- [ ] Workflow is active
- [ ] Test curl command returns AI response
- [ ] Arabic, French, English all work

---

## Next Steps

Once Phase 1 is working, proceed to **Phase 2 - FastAPI MCP Server** to add:
- Multi-tenant support (multiple businesses)
- Database integration
- Client configuration loading
- Conversation logging
