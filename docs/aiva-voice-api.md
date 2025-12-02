# AIVA Voice API - Technical Documentation

## Overview

The AIVA Voice API is a Node.js/Express service that provides enterprise-grade voice functionality for the AIVA ecosystem. It handles inbound/outbound Twilio calls with security features including rate limiting, Twilio signature validation, and session management.

## Deployment

**URL**: `https://aiva-voice-api.onrender.com`
**Repository**: `~/aiva-help-deploy/aiva-voice-api`
**Platform**: Render.com

## Endpoints

### Health Check

```
GET /health
```

**Response**:
```json
{
  "status": "healthy",
  "version": "2.0.0",
  "security": {
    "twilioValidation": true,
    "rateLimiting": true,
    "sessionManagement": true
  },
  "uptime": 12345
}
```

### Inbound Call Webhook

```
POST /voice/inbound
```

**Purpose**: Handle incoming Twilio calls

**Headers**:
- `X-Twilio-Signature`: Twilio signature for validation

**Body** (from Twilio):
- `CallSid`: Call identifier
- `From`: Caller phone number
- `To`: Called number

**Response**: TwiML for call handling

### Outbound Call Initiation

```
POST /voice/outbound
```

**Purpose**: Initiate outbound calls

**Headers**:
- `Content-Type: application/json`
- `X-API-Key`: AIVA API key (required)

**Body**:
```json
{
  "phone": "+61412345678",
  "name": "John Smith",
  "context": "callback request"
}
```

**Response**:
```json
{
  "success": true,
  "callSid": "CAxxxxxxxxx",
  "message": "Call initiated"
}
```

### Call Status Webhook

```
POST /voice/status
```

**Purpose**: Receive Twilio status callbacks

**Body** (from Twilio):
- `CallSid`: Call identifier
- `CallStatus`: Status (initiated, ringing, answered, completed, etc.)
- `Duration`: Call duration

## Security Features

### 1. Rate Limiting

- **Limit**: 30 requests per minute per IP
- **Window**: 60 seconds
- **Response on limit**: 429 Too Many Requests

### 2. Twilio Signature Validation

All `/voice/*` webhooks validate the `X-Twilio-Signature` header against the request body using the Twilio auth token.

### 3. API Key Authentication

Outbound calls require API key:
```
X-API-Key: your_api_key_here
```

### 4. Input Sanitization

Phone numbers are validated and sanitized:
- Australian mobiles: `04xxxxxxxx` → `+614xxxxxxxx`
- Australian landlines: `07xxxxxxxx` → `+617xxxxxxxx`
- Already formatted: `+61xxxxxxxxx` (kept as-is)

### 5. Session Management

SessionManager class provides:
- In-memory session storage (dev)
- Redis-ready interface (production)
- Session creation, retrieval, update
- Automatic expiration

## Environment Variables

```env
# Required
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=***
TWILIO_PHONE_NUMBER=+61720004410

# API Security
AIVA_API_KEY=your_api_key_here
BASE_URL=https://aiva-voice-api.onrender.com

# Optional
REDIS_URL=redis://...  # For production session storage
PORT=3000
```

## Code Structure

```
aiva-voice-api/
├── index.js           # Main Express app
├── package.json       # Dependencies
├── .env              # Local environment
└── .env.example      # Template

Key Components:
- SessionManager class
- validateTwilioSignature middleware
- rateLimiter middleware
- sanitizePhone utility
```

## Integration with AIVA Callback System

The Voice API works in conjunction with the Firebase Cloud Functions:

1. **ghlCallbackTrigger** → Initiates calls via Twilio REST API
2. **aivaTwilioBridge** → Provides TwiML for call handling
3. **AIVA Voice API** → Alternative deployment for more complex flows

## Testing

### Test Health
```bash
curl https://aiva-voice-api.onrender.com/health
```

### Test Outbound Call
```bash
curl -X POST https://aiva-voice-api.onrender.com/voice/outbound \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AIVA_API_KEY" \
  -d '{"phone": "+61412345678", "name": "Test"}'
```

## Deployment

### Deploy to Render

1. Push changes to repo:
```bash
cd ~/aiva-help-deploy/aiva-voice-api
git add -A
git commit -m "feat: Update voice API"
git push
```

2. Render auto-deploys from main branch

### Manual Deploy
```bash
# Via Render CLI or dashboard
render deploy --service aiva-voice-api
```

## Monitoring

### View Logs
```bash
# Via Render dashboard or CLI
render logs --service aiva-voice-api
```

### Key Metrics
- Request rate per endpoint
- Error rate (4xx, 5xx)
- Response time
- Active sessions

## Related Documentation

- [AIVA Callback System](./aiva-callback-system.md)
- [Twilio Documentation](https://www.twilio.com/docs/voice)
- [GHL Voice AI](https://help.gohighlevel.com/)

---

**Last Updated**: 2024-12-03
**Version**: 2.0.0
**Author**: Claude Code
