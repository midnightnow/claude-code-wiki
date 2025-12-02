# AIVA Callback System - Technical Documentation

## Overview

The AIVA Callback System enables automated phone callbacks from the aiva.help website. When users request a callback, the system intelligently routes the request based on phone type:

- **Mobile numbers**: Sends SMS with click-to-call link
- **Landlines**: Initiates direct outbound call with voice bridge

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      AIVA CALLBACK SYSTEM                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  User clicks "Call Me Back" on aiva.help                                │
│                    │                                                     │
│                    ▼                                                     │
│  ┌──────────────────────────────────────┐                               │
│  │     ghlCallbackTrigger               │ Firebase Cloud Function        │
│  │     (Main Entry Point)               │ us-central1                    │
│  └──────────────────────────────────────┘                               │
│                    │                                                     │
│         ┌─────────┴─────────┐                                           │
│         │                   │                                            │
│    Mobile Number       Landline/Other                                    │
│         │                   │                                            │
│         ▼                   ▼                                            │
│  ┌─────────────┐    ┌─────────────────┐                                 │
│  │  Send SMS   │    │  Direct Call    │                                 │
│  │  (Twilio)   │    │  via Twilio     │                                 │
│  └─────────────┘    └─────────────────┘                                 │
│         │                   │                                            │
│         ▼                   ▼                                            │
│  User clicks        ┌─────────────────┐                                 │
│  link in SMS        │ aivaTwilioBridge│  TwiML Handler                  │
│         │           │  (Voice Script) │                                 │
│         │           └─────────────────┘                                 │
│         │                   │                                            │
│         └───────────┬───────┘                                           │
│                     ▼                                                    │
│          ┌─────────────────────┐                                        │
│          │   +61 468 080 000   │  GHL Voice AI (Ava)                    │
│          │   AIVA Inbound      │                                        │
│          └─────────────────────┘                                        │
│                     │                                                    │
│                     ▼                                                    │
│          ┌─────────────────────┐                                        │
│          │ twilioCallStatus    │  Status Webhook                        │
│          │ (Updates Firestore) │                                        │
│          └─────────────────────┘                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Firebase Cloud Functions

### 1. ghlCallbackTrigger

**URL**: `https://us-central1-influential-digital-2025.cloudfunctions.net/ghlCallbackTrigger`

**Purpose**: Main callback request handler with intelligent routing

**Method**: POST

**Headers**:
- `Content-Type: application/json`
- `Origin`: Must be whitelisted domain

**Request Body**:
```json
{
  "phone": "0412345678",      // Required - Australian format
  "name": "John Smith",        // Optional
  "email": "john@example.com", // Optional
  "business": "Acme Corp",     // Optional
  "timing": "now",             // Options: now, 5min, 30min, later
  "source": "aiva.help"        // Optional - tracking source
}
```

**Response (SMS sent)**:
```json
{
  "success": true,
  "message": "SMS sent! Please check your phone and click the link to call us.",
  "messageSid": "SMxxxxxxxxxxxxxxxxx",
  "method": "sms"
}
```

**Response (Direct call initiated)**:
```json
{
  "success": true,
  "message": "Call incoming! AIVA is calling you now.",
  "callSid": "CAxxxxxxxxxxxxxxxxx",
  "method": "direct_call"
}
```

**Logic Flow**:
1. Format phone number to E.164 format (+61...)
2. Attempt SMS via Twilio US number (+1 351-200-9935)
3. If SMS fails (landline), fall back to direct outbound call
4. Log to GHL webhook for CRM tracking
5. Store callback request in Firestore

### 2. aivaTwilioBridge

**URL**: `https://us-central1-influential-digital-2025.cloudfunctions.net/aivaTwilioBridge`

**Purpose**: TwiML endpoint for outbound calls - bridges to GHL Voice AI

**Method**: GET

**Query Parameters**:
- `name`: Caller's name (for personalized greeting)
- `target`: Phone number to dial (defaults to +61468080000)

**Response**: TwiML XML
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say voice="Polly.Olivia" language="en-AU">
    Hi [name]! This is your callback from AIVA. Connecting you now...
  </Say>
  <Dial callerId="+13512009935" timeout="60">
    <Number>+61468080000</Number>
  </Dial>
  <Say voice="Polly.Olivia" language="en-AU">
    Sorry, we couldn't connect you. Please try calling us directly...
  </Say>
</Response>
```

### 3. aivaOutboundTwiml (Legacy)

**URL**: `https://us-central1-influential-digital-2025.cloudfunctions.net/aivaOutboundTwiml`

**Purpose**: Legacy TwiML for direct calls to Dallas (+61 7 4041 1000)

**Method**: GET

**Query Parameters**:
- `name`: Caller's name

### 4. twilioCallStatus

**URL**: `https://us-central1-influential-digital-2025.cloudfunctions.net/twilioCallStatus`

**Purpose**: Webhook for Twilio call status updates

**Method**: POST

**Body** (Twilio sends):
- `CallSid`: Unique call identifier
- `CallStatus`: initiated, ringing, answered, completed, busy, no-answer, failed
- `Duration`: Call duration in seconds
- `To`, `From`: Phone numbers

**Updates**:
- Firestore `callback-requests` collection with call status
- Firestore `call-status-events` collection for audit log

## Twilio Configuration

### Phone Numbers

| Number | Type | Purpose |
|--------|------|---------|
| +61 7 2000 4410 | AU Local | Outbound calls (caller ID) |
| +1 351-200-9935 | US Local | SMS sending |
| +61 468 080 000 | AU Mobile | GHL Voice AI inbound (Ava) |

### Account Credentials

Stored in Firebase Functions Config:
```bash
firebase functions:config:get --project influential-digital-2025
```

```json
{
  "twilio": {
    "account_sid": "ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "auth_token": "***",
    "phone_number": "+61720004410"
  }
}
```

## Firestore Collections

### callback-requests

```javascript
{
  phone: "+61412345678",
  name: "John Smith",
  email: "john@example.com",
  source: "aiva.help callback",
  timing: "now",
  business: "Acme Corp",
  status: "call_initiated" | "sms_sent" | "failed",
  method: "sms" | "direct_call",
  twilioMessageSid: "SMxxx", // If SMS
  twilioCallSid: "CAxxx",   // If call
  twilioError: null,        // Error message if failed
  twilioStatus: "completed" | "no-answer" | etc,
  twilioUpdatedAt: Timestamp,
  callDuration: 120,
  createdAt: Timestamp
}
```

### call-status-events

```javascript
{
  callSid: "CAxxxxxxxxx",
  status: "answered",
  to: "+61412345678",
  from: "+61720004410",
  duration: 120,
  timestamp: Timestamp
}
```

## CORS Configuration

Allowed origins for callback requests:
- `https://aiva.help`
- `https://aiva-help.web.app`
- `https://aiva.tax`
- `https://aiva-tax.web.app`
- `https://aiva.support`
- `http://localhost:5000` (dev)
- `http://localhost:3000` (dev)

## GHL Integration

### Webhook URL
```
https://services.leadconnectorhq.com/hooks/Px7kCAZIXCP2Kk8vs7IO/webhook-trigger/bd331aa5-7168-4b35-beb5-4907da23923a
```

### Payload sent to GHL
```json
{
  "phone": "+61412345678",
  "name": "John Smith",
  "email": "john@example.com",
  "source": "aiva.help callback",
  "timing": "now",
  "business": "Acme Corp",
  "timestamp": "2024-12-03T10:30:00Z",
  "action": "sms_callback" | "direct_call",
  "twilioMessageSid": "SMxxx",
  "twilioCallSid": "CAxxx"
}
```

## Testing

### Test SMS (Mobile)
```bash
curl -X POST "https://us-central1-influential-digital-2025.cloudfunctions.net/ghlCallbackTrigger" \
  -H "Content-Type: application/json" \
  -H "Origin: https://aiva.help" \
  -d '{"phone":"0412345678","name":"Test User"}'
```

### Test Direct Call (Landline)
```bash
curl -X POST "https://us-central1-influential-digital-2025.cloudfunctions.net/ghlCallbackTrigger" \
  -H "Content-Type: application/json" \
  -H "Origin: https://aiva.help" \
  -d '{"phone":"0740411000","name":"Test User"}'
```

### Test TwiML Endpoint
```bash
curl "https://us-central1-influential-digital-2025.cloudfunctions.net/aivaTwilioBridge?name=Test&target=%2B61468080000"
```

## Deployment

```bash
cd ~/influential-digital-site

# Deploy all callback functions
firebase deploy --only functions:ghlCallbackTrigger,functions:aivaTwilioBridge,functions:aivaOutboundTwiml,functions:twilioCallStatus --project influential-digital-2025
```

## Troubleshooting

### SMS fails with "cannot be a landline"
- Expected behavior - system automatically falls back to direct call

### Call shows "no-answer"
- User didn't pick up within timeout (60 seconds)
- Check if number is correct
- Verify Twilio account has sufficient balance

### Call shows "failed"
- Check Twilio geo-permissions for Australia
- Verify phone number format is correct
- Check Firebase function logs

### View Logs
```bash
firebase functions:log --only ghlCallbackTrigger -n 50 --project influential-digital-2025
```

---

**Last Updated**: 2024-12-03
**Version**: 2.0.0
**Author**: Claude Code
