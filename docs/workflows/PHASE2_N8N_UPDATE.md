# Phase 2 n8n Workflow Update Guide

## Overview

Update your Phase 1 workflow to integrate with the FastAPI backend for multi-tenant support.

## Prerequisites

1. FastAPI backend running on http://localhost:8000
2. Database seeded with at least one business
3. Backend API accessible from n8n

## New Nodes to Add

### Before AI Agent (Config Loading)

#### Node A: Get Business ID
- **Type**: HTTP Request
- **Name**: "Get Business ID"
- **Method**: GET
- **URL**: `http://localhost:8000/client/by-phone/{{ $json.business_number }}`
- **Response Format**: JSON

#### Node B: Load Business Config
- **Type**: HTTP Request
- **Name**: "Load Config"
- **Method**: GET
- **URL**: `http://localhost:8000/client/config/{{ $json.business_id }}`
- **Response Format**: JSON

### After AI Agent (Conversation Logging)

#### Node C: Log User Message
- **Type**: HTTP Request
- **Name**: "Log User Message"
- **Method**: POST
- **URL**: `http://localhost:8000/conversation/log`
- **Body** (JSON):
```json
{
  "business_id": "={{ $json.business_id }}",
  "customer_phone": "={{ $json.user_phone }}",
  "role": "user",
  "message": "={{ $json.message_text }}"
}
```

#### Node D: Log Assistant Reply
- **Type**: HTTP Request
- **Name**: "Log Assistant Reply"
- **Method**: POST
- **URL**: `http://localhost:8000/conversation/log`
- **Body** (JSON):
```json
{
  "business_id": "={{ $json.business_id }}",
  "customer_phone": "={{ $json.user_phone }}",
  "role": "assistant",
  "message": "={{ $json.output }}"
}
```

## AI Agent Update

Change the **System Prompt** from hardcoded to:
```
={{ $json.system_prompt }}
```

## Updated Workflow Flow

```
Webhook → Parse Payload → Get Business ID → Load Config → AI Agent → Log User Message → Log Assistant Reply → Respond to Webhook
                                                            ↓
                                                       Groq Chat Model
```

## Data Flow Explanation

1. **Webhook**: Receives message with phone numbers
2. **Parse Payload**: Extracts message_text, user_phone, business_number
3. **Get Business ID**: API call to get business_id for the business_number
4. **Load Config**: API call to get system_prompt and enabled_tools
5. **AI Agent**: Uses dynamic system_prompt, generates response
6. **Log Messages**: Both user and assistant messages logged to database
7. **Respond to Webhook**: Returns reply to caller

## Testing

### Test with Business Phone (Test Clinic)
```bash
curl -X POST http://localhost:5678/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "message_text": "I want to book an appointment",
    "from": "96170000001",
    "to": "96171000002"
  }'
```

Expected: Clinic-specific response about appointments

### Test with Another Business (Test Restaurant)
```bash
curl -X POST http://localhost:5678/webhook/whatsapp \
  -H "Content-Type: application/json" \
  -d '{
    "message_text": "What are your hours?",
    "from": "96170000002",
    "to": "96171000003"
  }'
```

Expected: Restaurant-specific response (FAQ only, no appointments)

## Verification

After updating the workflow:

1. [ ] Activate workflow
2. [ ] Test with different phone numbers
3. [ ] Check backend: conversations logged in database
4. [ ] Check admin dashboard: view conversations
5. [ ] Verify different system prompts per business
