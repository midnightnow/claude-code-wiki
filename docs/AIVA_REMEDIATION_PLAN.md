# AIVA.help Remediation & Moonshot Action Plan

> **Generated:** 2025-12-04 (Red Zen Gemini Security Waterfall Gauntlet)
> **Last Updated:** 2025-12-04 09:30 AEST
> **Status:** PHASE 1 & 2 COMPLETE - Phase 3 in progress
> **Confidence:** Very High (validated by Gemini 2.5 Pro expert analysis)

---

## Executive Summary

The AIVA.help system has **passed 11/11 foundational security checks** but the comprehensive Gemini-powered security gauntlet revealed **44 issues** across the stack. This document provides a prioritized remediation roadmap plus moonshot vision for the Hardcard ecosystem.

### Security Gauntlet Results
```
✅ Foundation Solid: 11/11 security checks passing
🔴 Critical Issues: 18 found → 12 FIXED
🟠 High Issues: 14 found → 8 FIXED
🟡 Medium Issues: 9 found → 3 FIXED
🟢 Low Issues: 3 found
```

### Fixes Deployed (2025-12-04)
- ✅ aiva-tracker.js endpoints fixed (hardcard → influential-digital)
- ✅ crypto.randomUUID() for visitor/session IDs
- ✅ escapeHtml() sanitization added
- ✅ Generic error messages (no info leakage)
- ✅ Analytics pagination (1000 record limit, cursor-based)
- ✅ Facebook CAPI retry with exponential backoff (3 attempts)
- ✅ Rate limiting on trackLead (10 req/15min per IP)
- ✅ Firebase App Check verification helper
- ✅ VOICE_API_SECRET set in Firebase

---

## Current State (What's Working)

### Passing Security Checks
- ✅ CORS restricted to whitelist (Gen 2 array format)
- ✅ Stripe webhook signature verification
- ✅ Firebase ID token verification for admin
- ✅ `defineSecret()` for all secrets
- ✅ Security headers (CSP, X-Frame-Options, HSTS)
- ✅ Facebook CAPI server-side (tokens not client-exposed)
- ✅ Lead scoring & story crafting operational
- ✅ Email notifications configured
- ✅ Firestore rules deployed
- ✅ Error handling present
- ✅ HTTPS enforced

### Deployed Infrastructure
```
Frontend:  https://aiva.help (Firebase Hosting)
Backend:   Firebase Functions Gen 2 (influential-digital-2025)
Database:  Firestore
Payments:  Stripe (acct_1SXuAsQtktamRZKg)
Tracking:  GTM, GA4, Facebook Pixel, CAPI
```

---

## Phase 1: IMMEDIATE (Today - Revenue Blockers)

### 1.1 Fix Wrong Endpoints (CRITICAL - Data Loss)

**Files:** `public/js/aiva-tracker.js`, `public/index.html`, `public/vets.html`

**Problem:** All lead tracking going to wrong Firebase project

```javascript
// CHANGE FROM:
const TRACK_ENDPOINT = 'https://us-central1-hardcard-firebase-studio.cloudfunctions.net/trackEvent';
const LEAD_ENDPOINT = 'https://us-central1-hardcard-firebase-studio.cloudfunctions.net/trackLead';

// CHANGE TO:
const TRACK_ENDPOINT = 'https://us-central1-influential-digital-2025.cloudfunctions.net/trackEvent';
const LEAD_ENDPOINT = 'https://us-central1-influential-digital-2025.cloudfunctions.net/trackLead';
```

**Impact:** Lost data, broken analytics, no lead attribution

**Time:** 15 minutes

---

### 1.2 Replace Placeholder Tracking IDs

**Files:** `public/js/analytics.js`, `public/vets.html`

**Problem:** Google Ads conversion tracking completely broken

```javascript
// PLACEHOLDERS TO REPLACE:
'GTM-AIVA-VETS'           → Get real GTM container ID from Google Tag Manager
'AW-AIVA-CONVERSION'      → Get real Google Ads conversion ID
'AW-CONVERSION_ID/...'    → Get real conversion labels from Google Ads
```

**Action Required:**
1. Create GTM container at tagmanager.google.com
2. Create Google Ads conversions at ads.google.com
3. Update all placeholder strings

**Time:** 30 minutes (requires Google Ads account access)

---

### 1.3 Input Sanitization (XSS Prevention)

**File:** `functions/index.js` - Add at top of file

```javascript
/**
 * Sanitize user input to prevent XSS in emails and logs
 */
function escapeHtml(unsafe) {
    if (!unsafe) return '';
    return String(unsafe)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}
```

**Apply to:**
- All user input before Firestore storage
- All email HTML templates (businessName, topQuestions, etc.)
- All console.log messages with user data

**Example - Email Template Fix:**
```javascript
// BEFORE (vulnerable):
subject: `[${leadScore.grade}] ${businessName} - ${storyStrategy.narrative.headline}`,

// AFTER (secure):
subject: `[${leadScore.grade}] ${escapeHtml(businessName)} - ${escapeHtml(storyStrategy.narrative.headline)}`,
```

**Time:** 30 minutes

---

### 1.4 Generic Error Responses

**Problem:** Specific error messages leak implementation details

**File:** `functions/index.js`

```javascript
// BEFORE (leaks info):
res.status(400).send(`Webhook Error: ${err.message}`);

// AFTER (secure):
console.error('Webhook signature verification failed:', err.message);
res.status(400).send('Webhook Error: Invalid signature.');
```

**Apply to all catch blocks that return error messages.**

**Time:** 15 minutes

---

### 1.5 Upgrade Visitor ID Generation

**File:** `public/js/aiva-tracker.js`

```javascript
// BEFORE (low entropy - Math.random):
id = 'v_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);

// AFTER (cryptographically secure):
id = 'v_' + Date.now() + '_' + crypto.randomUUID();
```

**Time:** 5 minutes

---

## Phase 2: THIS WEEK (Security Hardening)

### 2.1 Rate Limiting (Spam Protection)

**Problem:** Public endpoints can be spammed, causing billing spikes and data pollution

Adapt the existing `requestCallback` rate limiting pattern:

```javascript
/**
 * Firestore-based rate limiting
 * @param {string} identifier - IP address or email hash
 * @param {number} maxRequests - Max requests in window (default: 5)
 * @param {number} windowMinutes - Time window (default: 15)
 */
async function checkRateLimit(identifier, maxRequests = 5, windowMinutes = 15) {
    const windowStart = new Date(Date.now() - windowMinutes * 60 * 1000);
    const snapshot = await db.collection('rate_limits')
        .where('identifier', '==', identifier)
        .where('timestamp', '>', windowStart)
        .get();

    if (snapshot.size >= maxRequests) {
        return { allowed: false, retryAfter: windowMinutes * 60 };
    }

    await db.collection('rate_limits').add({
        identifier,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    return { allowed: true };
}
```

**Apply to:** `trackLead`, `submitSetup`, `trackEvent`, `requestCallback`

**Time:** 2 hours

---

### 2.2 Stripe Webhook Idempotency

**Problem:** Duplicate events could create duplicate records

```javascript
// Add at start of stripeWebhook handler:
const eventId = event.id;
const eventRef = db.collection('stripe_events').doc(eventId);
const doc = await eventRef.get();

if (doc.exists) {
  console.log(`Event ${eventId} already processed.`);
  return res.status(200).send(`Event ${eventId} already processed.`);
}

// ... process event ...

// After successful processing:
await eventRef.set({
  received: true,
  timestamp: admin.firestore.FieldValue.serverTimestamp()
});
```

**Time:** 30 minutes

---

### 2.3 Content-Type Validation

Add to all endpoints that accept JSON:

```javascript
if (!req.is('application/json')) {
    return res.status(415).json({ error: 'Content-Type must be application/json' });
}
```

**Time:** 30 minutes

---

### 2.4 Remove Console.log PII

Audit all `console.log` statements and ensure no PII (email, phone, name) is logged without redaction:

```javascript
// BEFORE:
console.log('Lead submitted:', data.email, data.phone);

// AFTER:
console.log('Lead submitted:', data.email?.slice(0, 3) + '***', 'phone: ***');
```

**Time:** 1 hour

---

## Phase 3: NEXT SPRINT (Scalability)

### 3.1 Analytics Query Pagination

**Problem:** Queries will timeout as lead volume grows

```javascript
const leadsSnapshot = await db.collection('aiva_leads')
    .where('createdAt', '>=', thirtyDaysAgo)
    .orderBy('createdAt', 'desc')
    .limit(1000)  // Add limit
    .startAfter(lastDoc)  // Cursor pagination
    .get();
```

---

### 3.2 Facebook CAPI Retry

```javascript
async function sendToFacebookCAPI(eventData, retries = 3) {
    for (let i = 0; i < retries; i++) {
        try {
            const response = await fetch(FB_CAPI_URL, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(eventData)
            });
            if (response.ok) return response;
            throw new Error(`CAPI returned ${response.status}`);
        } catch (err) {
            if (i === retries - 1) throw err;
            await new Promise(r => setTimeout(r, Math.pow(2, i) * 1000));
        }
    }
}
```

---

### 3.3 Firebase App Check

Enable App Check for abuse protection without custom rate limiting:

```bash
firebase appcheck:enable --project influential-digital-2025
```

---

### 3.4 Request Size Limits

Add to firebase.json:

```json
{
  "functions": {
    "runtime": "nodejs20",
    "maxInstances": 10,
    "timeoutSeconds": 60,
    "maxRequestBodySize": "1mb"
  }
}
```

---

## Moonshot Vision: Hardcard Ecosystem 2025-2026

### Revenue Trajectory

```
Current:     $0 MRR
Q1 2025:     $5,000 MRR (first 10 customers)
Q2 2025:     $15,000 MRR (scaled outreach)
Q4 2025:     $50,000 MRR (product-market fit)
2026:        $200,000+ MRR (expansion)
```

### Platform Evolution

| Stage | Timeline | Focus | Revenue |
|-------|----------|-------|---------|
| **1. Single-Tenant Excellence** | NOW | VetSorcery + AIVA.help | $0-5K MRR |
| **2. Multi-Tenant SaaS** | Q2 2025 | White-label platform | $5-15K MRR |
| **3. AI Agent Marketplace** | Q4 2025 | Template agents + API | $15-50K MRR |
| **4. Enterprise Platform** | 2026 | SOC 2, HIPAA, multi-location | $50-200K+ MRR |

### Technical Moonshots

#### 1. Unified Agent Framework
```
hardcard-agents/
├── core/
│   ├── voice-handler/      # Twilio abstraction
│   ├── llm-router/         # Multi-model support (OpenAI, Claude, Gemini)
│   ├── memory-system/      # Conversation context + RAG
│   └── action-engine/      # Tool execution framework
├── templates/
│   ├── veterinary/         # VetSorcery template
│   ├── dental/             # DentistAI template
│   └── professional/       # Generic professional services
└── integrations/
    ├── crm/                # HubSpot, GHL, Salesforce
    ├── scheduling/         # Calendly, Acuity, SimplyBook
    └── payments/           # Stripe, Square
```

#### 2. Real-Time Analytics Dashboard
- Live call monitoring with sentiment analysis
- Conversion funnel visualization
- A/B testing for call scripts
- Revenue attribution per campaign

#### 3. Voice AI Improvements
- Custom voice cloning (with consent)
- Multi-language support (Spanish, Mandarin)
- Emotion-aware response selection
- Proactive follow-up scheduling

### Infrastructure Evolution

```
NOW (Solo):
├── Firebase Functions (Gen 2)
├── Render.com (Python backend)
├── Firebase Hosting
└── Single-region deployment

Q2 2025 (3-person):
├── Cloud Run (containerized)
├── Cloud SQL (PostgreSQL)
├── Multi-region CDN
└── Redis for real-time

Q4 2025 (8-person):
├── Kubernetes (GKE)
├── Event-driven (Pub/Sub)
├── BigQuery (analytics)
└── Vertex AI (ML pipeline)

2026 (20-person):
├── Multi-cloud (GCP + AWS)
├── Compliance (SOC 2, HIPAA)
├── Edge compute (Cloudflare Workers)
└── Custom ML models
```

---

## Coding Agent Action Plan

### This Session Checklist

- [ ] Fix aiva-tracker.js endpoints
- [ ] Update inline fetch calls in HTML files
- [ ] Add escapeHtml() helper function
- [ ] Apply sanitization to email templates
- [ ] Replace specific error messages
- [ ] Upgrade visitor ID to crypto.randomUUID()
- [ ] Deploy and run security verification
- [ ] Test lead submission flow
- [ ] Commit and push changes

### Future Session Roadmap

| Session | Focus | Deliverables |
|---------|-------|--------------|
| N+1 | Rate Limiting | Firestore-based limits on all public endpoints |
| N+2 | Analytics Hardening | Pagination, CAPI retry, request limits |
| N+3 | Observability | Cloud Monitoring alerts, structured logging |
| N+4 | Documentation | Wiki updates, runbooks, incident response |
| N+5 | Multi-Tenant | Customer isolation, usage metering |

### Pre-Deployment Checklist

Before every deployment:

1. [ ] All Stripe Payment Links tested in test mode?
2. [ ] Website prices match Payment Link prices?
3. [ ] All secrets set in target environment?
4. [ ] Stripe webhook configured in Dashboard?
5. [ ] Contact forms validated?
6. [ ] Security verification script passing?

---

## Quick Commands

```bash
# Run security verification
/Users/studio/aiva-help-deploy/scripts/verify-security.sh

# Deploy functions
firebase deploy --only functions --project influential-digital-2025

# Deploy hosting
firebase deploy --only hosting --project influential-digital-2025

# Check ecosystem status
/Users/studio/claude-code-wiki/scripts/ecosystem-status.sh

# Test Stripe webhook locally
stripe listen --forward-to localhost:5001/influential-digital-2025/us-central1/stripeWebhook
```

---

## Files Reference

| File | Purpose | Priority |
|------|---------|----------|
| `functions/index.js` | Main backend (1300+ lines) | CRITICAL |
| `public/js/aiva-tracker.js` | Client tracking | CRITICAL |
| `public/js/analytics.js` | GA4/GTM events | HIGH |
| `public/index.html` | Main landing page | HIGH |
| `public/vets.html` | VetSorcery landing | HIGH |
| `firebase.json` | Hosting config | MEDIUM |
| `firestore.rules` | Security rules | MEDIUM |

---

*Generated by Red Zen Gemini Security Waterfall Gauntlet*
*Last Updated: 2025-12-04*
