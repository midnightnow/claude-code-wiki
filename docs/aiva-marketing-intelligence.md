# AIVA Marketing Intelligence System - Technical Documentation

## Overview

The AIVA Marketing Intelligence System is a comprehensive lead tracking, attribution, and automated nurturing system for aiva.help. It captures visitor behavior, calculates lead quality scores, determines optimal follow-up strategies, and integrates with Facebook/Meta for conversion optimization.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     AIVA MARKETING INTELLIGENCE SYSTEM                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  Visitor arrives on aiva.help                                                   │
│           │                                                                      │
│           ▼                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐              │
│  │              TRACKING LAYER (Client-Side)                      │              │
│  ├───────────────────────────────────────────────────────────────┤              │
│  │  • Google Tag Manager (GTM-PBXJ52FC)                          │              │
│  │  • Facebook Pixel (1098204243523075)                          │              │
│  │  • Microsoft Clarity (qf8j4qwo8l)                             │              │
│  │  • aiva-tracker.js (UTM capture, scroll, clicks)              │              │
│  └───────────────────────────────────────────────────────────────┘              │
│           │                                                                      │
│           ▼                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐              │
│  │              FIREBASE CLOUD FUNCTIONS                          │              │
│  ├───────────────────────────────────────────────────────────────┤              │
│  │  trackEvent          → Page views, scroll depth, clicks        │              │
│  │  trackLead           → Lead capture + scoring + story strategy │              │
│  │  getMarketingAnalytics → Admin dashboard data                  │              │
│  │  exportRetargetingAudience → FB/Google audience export         │              │
│  └───────────────────────────────────────────────────────────────┘              │
│           │                                                                      │
│     ┌─────┴─────┐                                                               │
│     │           │                                                                │
│     ▼           ▼                                                                │
│  Firestore   Facebook CAPI                                                      │
│  Database    (Server-side conversion)                                           │
│     │                                                                            │
│     ▼                                                                            │
│  ┌───────────────────────────────────────────────────────────────┐              │
│  │              ADMIN DASHBOARD                                   │              │
│  │              https://aiva.help/admin/                         │              │
│  └───────────────────────────────────────────────────────────────┘              │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Client-Side Tracking

### 1. Google Tag Manager (GTM-PBXJ52FC)

**Purpose**: Container for all Google tags (GA4, Google Ads conversions)

**Location**: All HTML pages in `<head>`
```javascript
(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
'https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);
})(window,document,'script','dataLayer','GTM-PBXJ52FC');
```

### 2. Facebook Pixel (1098204243523075)

**Purpose**: Track PageView, ViewContent, and Lead events for Meta Ads optimization

**Events Tracked**:
- `PageView` - Automatic on every page
- `ViewContent` - On landing pages (vets.html)
- `Lead` - On form submission (CRITICAL for AdEspresso)

**Lead Event Implementation** (in handleSignup function):
```javascript
if (window.fbq) {
    fbq('track', 'Lead', {
        content_name: formData.businessName,
        content_category: 'AIVA Signup',
        value: formData.plan === 'enterprise' ? 499 : formData.plan === 'professional' ? 199 : 99,
        currency: 'AUD'
    });
    console.log('✅ Facebook Lead pixel fired');
}
```

### 3. Microsoft Clarity (qf8j4qwo8l)

**Purpose**: Free heatmaps and session recordings

**Location**: index.html, vets.html, blog/index.html

**Dashboard**: https://clarity.microsoft.com/projects

```javascript
(function(c,l,a,r,i,t,y){
    c[a]=c[a]||function(){(c[a].q=c[a].q||[]).push(arguments)};
    t=l.createElement(r);t.async=1;t.src="https://www.clarity.ms/tag/"+i;
    y=l.getElementsByTagName(r)[0];y.parentNode.insertBefore(t,y);
})(window, document, "clarity", "script", "qf8j4qwo8l");
```

### 4. aiva-tracker.js

**Location**: `/public/js/aiva-tracker.js`

**Purpose**: Custom tracking script for:
- Visitor ID persistence
- Session management (30-min timeout)
- UTM parameter capture and storage
- First-touch / last-touch attribution
- Scroll depth tracking (25%, 50%, 75%, 90%)
- CTA click tracking
- Form interaction tracking

**Public API**:
```javascript
window.AIVATracker = {
    trackEvent(eventType, metadata),   // Track custom events
    trackLead(formData),               // Track lead with full attribution
    getTrackingData(),                 // Get all stored tracking data
    getVisitorId(),                    // Get persistent visitor ID
    getSessionId(),                    // Get current session ID
    getUTMParams()                     // Get stored UTM parameters
};
```

**Storage Keys** (localStorage):
| Key | Purpose |
|-----|---------|
| `aiva_visitor_id` | Persistent visitor identifier |
| `aiva_utm_source` | First-touch UTM source |
| `aiva_utm_medium` | First-touch UTM medium |
| `aiva_utm_campaign` | First-touch UTM campaign |
| `aiva_utm_content` | First-touch UTM content |
| `aiva_utm_term` | First-touch UTM term |
| `aiva_fbclid` | Facebook Click ID |
| `aiva_first_touch` | Timestamp of first visit |
| `aiva_landing_page` | First page visited |

---

## Firebase Cloud Functions

### 1. trackEvent

**URL**: `https://us-central1-influential-digital-2025.cloudfunctions.net/trackEvent`

**Purpose**: Track visitor events (pageviews, scroll depth, clicks)

**Method**: POST

**Request Body**:
```json
{
  "visitorId": "v_1234567890_abc123",
  "sessionId": "s_1234567890_xyz789",
  "eventType": "pageview",
  "page": "/vets",
  "referrer": "https://facebook.com",
  "screenWidth": 1920,
  "screenHeight": 1080,
  "utm_source": "facebook",
  "utm_medium": "cpc",
  "utm_campaign": "vets-retarget-dec",
  "fbclid": "abc123",
  "metadata": {}
}
```

**Response**:
```json
{
  "success": true,
  "visitorId": "v_1234567890_abc123",
  "sessionId": "s_1234567890_xyz789"
}
```

**Firestore Collections Updated**:
- `aiva_events` - Event log
- `aiva_visitors` - Visitor profile (aggregated)

---

### 2. trackLead

**URL**: `https://us-central1-influential-digital-2025.cloudfunctions.net/trackLead`

**Purpose**: Capture lead with full attribution, calculate score, determine story strategy

**Method**: POST

**Secrets Required**:
- `EMAIL_USER` = `dallas@rhizosciences.com` (v2)
- `EMAIL_PASS` = App password 'aiva' (v4)
- `FB_ACCESS_TOKEN` = Meta CAPI token (v2)

See `/docs/google-workspace-infrastructure.md` for email configuration details.

**Request Body**:
```json
{
  "businessName": "Happy Paws Vet",
  "email": "clinic@happypaws.com",
  "forwardNumber": "+61740411000",
  "website": "happypaws.com",
  "industry": "veterinary",
  "hours": "8am-6pm Mon-Fri",
  "topQuestions": "After-hours emergencies, pricing, availability",
  "specialInstructions": "Always transfer urgent calls",
  "utm_source": "facebook",
  "utm_medium": "cpc",
  "utm_campaign": "vets-retarget-dec",
  "fbclid": "abc123",
  "visitorId": "v_123",
  "sessionId": "s_456",
  "landingPage": "/vets",
  "firstTouchTimestamp": "2024-12-01T10:00:00Z"
}
```

**Response**:
```json
{
  "success": true,
  "leadId": "abc123xyz",
  "score": 85,
  "grade": "A"
}
```

**Processing Pipeline**:
1. Calculate lead score (0-100)
2. Determine story strategy based on source + grade
3. Store lead in Firestore
4. Send notification email with strategy recommendation
5. Fire Facebook CAPI conversion event
6. Return score/grade to client for GTM dataLayer

---

## Lead Scoring Algorithm

### Score Components (Max 100 points)

| Factor | Max Points | Logic |
|--------|------------|-------|
| Source Quality | 30 | google=25, facebook=20, linkedin=22, referral=30, direct=15, organic=18 |
| Industry Fit | 25 | veterinary/dental/medical/legal/accounting = 25, other = 10 |
| Completeness | 20 | (filled fields / total fields) * 20 |
| Engagement | 15 | Detailed questions (+10), Special instructions (+5) |
| Campaign | 10 | Retargeting campaign (+10), Any campaign (+5) |

### Grade Mapping

| Score Range | Grade | Priority |
|-------------|-------|----------|
| 80-100 | A | URGENT - Call immediately |
| 60-79 | B | HIGH - Case study sequence |
| 40-59 | C | MEDIUM - Nurture sequence |
| 0-39 | D | LOW - Long-term drip |

---

## Story Crafting System

The Story Crafting System determines the optimal narrative approach and email sequence for each lead based on traffic source and quality grade.

### Source-Based Narratives

| Source | Theme | Headline | Angle | Tone |
|--------|-------|----------|-------|------|
| Google | answer | "You searched, we answered" | Direct solution | efficient, expert, no-nonsense |
| Facebook | dream | "Imagine never missing a call again" | Aspiration | inspiring, visual, story-driven |
| LinkedIn | expert | "What top practices are doing differently" | Authority | professional, data-driven |
| Referral | club | "Welcome to the inner circle" | Social proof | warm, exclusive, community |
| Direct | home | "Welcome back - let's get started" | Familiarity | warm, efficient, action-oriented |

### Grade-Based Sequences

#### Grade A: VIP Founder Outreach
```
Priority: URGENT
Sales Alert: YES

Day 0 (+1 hour): Founder personal email
Day 1: Case study matched to industry
Day 2: Calendar invite for demo call
```

#### Grade B: Case Study Sequence
```
Priority: HIGH
Sales Alert: NO

Day 0 (+30 min): Welcome email (tailored to industry)
Day 1: Relevant case study
Day 3: ROI calculator tool
Day 7: Offer discovery call
```

#### Grade C: Educational Nurture
```
Priority: MEDIUM
Sales Alert: NO

Day 0 (+1 hour): Welcome educational email
Day 4: Problem agitation (missed calls cost)
Day 10: Solution introduction
Day 21: Case study
Day 35: Offer free trial
```

#### Grade D: Long-term Drip
```
Priority: LOW
Sales Alert: NO

Day 0 (+2 hours): Welcome value email
Day 14: Industry insight
Day 30: Success story
Day 60: Re-engagement offer
```

### Implementation

```javascript
function getStoryStrategy(grade, source, campaign) {
  // Returns:
  // {
  //   narrative: { theme, headline, angle, urgency, tone },
  //   sequence: { priority, action, sequence[], emailSubject, salesAlert },
  //   sourceKey, grade, isRetarget, recommendedAction
  // }
}
```

---

## Facebook Conversions API (CAPI)

### Purpose
Server-side event tracking to:
- Capture iOS 14+ users (blocked by App Tracking Transparency)
- Improve match rate for conversions
- Enable Meta AI optimization on actual leads (not just clicks)

### Configuration

**Pixel ID**: `1098204243523075`

**Access Token**: Firebase Secret `FB_ACCESS_TOKEN`
- Generate at: https://business.facebook.com/events_manager2/list/pixel/1098204243523075/settings
- Conversions API → Generate access token

### Event Payload
```javascript
{
  event_name: "Lead",
  event_time: 1701619200,
  action_source: "website",
  event_source_url: "https://aiva.help",
  user_data: {
    em: ["sha256_hashed_email"],
    client_ip_address: "1.2.3.4",
    client_user_agent: "Mozilla/5.0...",
    fbc: "fb.1.1701619200.abc123"  // From fbclid
  },
  custom_data: {
    content_name: "Happy Paws Vet",
    content_category: "veterinary",
    value: 500,  // Grade A = $500, B = $300, C/D = $100
    currency: "AUD"
  }
}
```

### API Endpoint
```
POST https://graph.facebook.com/v18.0/1098204243523075/events?access_token={FB_ACCESS_TOKEN}
```

---

## Admin Dashboard

**URL**: https://aiva.help/admin/

**Authentication**: Bearer token `aiva2025admin`

### Marketing Tab Features

1. **Summary Stats**
   - Total leads (30 days)
   - Leads last 7 days
   - Average lead score
   - Conversion rate

2. **Source Breakdown**
   - Leads by utm_source (pie chart)
   - Google vs Facebook vs Direct

3. **Campaign Performance Table**
   - Campaign name
   - Lead count
   - Average score
   - Source

4. **Hot Leads** (Grade A & B)
   - Business name
   - Email
   - Score & grade
   - Source & campaign
   - Timestamp

5. **Retargeting Audience Export**
   - Export hashed emails for FB Custom Audiences
   - Filter by grade (all / high_value)

---

## Firestore Collections

### aiva_leads
```javascript
{
  businessName: "Happy Paws Vet",
  email: "clinic@happypaws.com",
  phone: "+61740411000",
  website: "happypaws.com",
  industry: "veterinary",
  hours: "8am-6pm Mon-Fri",

  topQuestions: "...",
  specialInstructions: "...",

  // Attribution
  firstTouch: {
    utm_source: "facebook",
    utm_medium: "cpc",
    utm_campaign: "vets-retarget",
    utm_content: null,
    utm_term: null,
    fbclid: "abc123",
    gclid: null,
    landingPage: "/vets",
    timestamp: "2024-12-01T10:00:00Z"
  },
  lastTouch: {
    utm_source: "facebook",
    page: "/",
    referrer: "https://facebook.com"
  },

  // Tracking
  visitorId: "v_123",
  sessionId: "s_456",

  // Scoring
  leadScore: 85,
  leadGrade: "A",
  scoreSignals: [
    { factor: "source", value: "facebook", points: 20 },
    { factor: "industry_fit", value: "veterinary", points: 25 },
    // ...
  ],

  // Story Strategy
  storyStrategy: {
    narrative: "dream",
    sequence: "sales_alert",
    priority: "urgent",
    isRetarget: true
  },

  // Metadata
  userAgent: "Mozilla/5.0...",
  ip: "1.2.3.4",
  source: "web_form",
  status: "new",
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### aiva_events
```javascript
{
  visitorId: "v_123",
  sessionId: "s_456",
  eventType: "pageview" | "scroll_depth" | "cta_click" | "form_start",
  page: "/vets",
  referrer: "https://facebook.com",
  userAgent: "...",
  ip: "1.2.3.4",

  utm_source: "facebook",
  utm_medium: "cpc",
  utm_campaign: "vets-retarget",
  fbclid: "abc123",

  screenWidth: 1920,
  screenHeight: 1080,

  metadata: {
    depth: 75,  // For scroll_depth
    text: "Get Started",  // For cta_click
  },

  timestamp: Timestamp
}
```

### aiva_visitors
```javascript
{
  lastSeen: Timestamp,
  sessionCount: 3,
  pageviews: 12,

  firstTouch: {
    utm_source: "facebook",
    utm_medium: "cpc",
    utm_campaign: "vets-retarget",
    landingPage: "/vets",
    timestamp: Timestamp
  },

  lastTouch: {
    utm_source: "google",
    page: "/pricing",
    timestamp: Timestamp
  }
}
```

---

## Deployment

### Deploy Marketing Functions
```bash
cd ~/aiva-help-deploy

# Deploy all marketing functions
firebase deploy --only functions:trackEvent,functions:trackLead,functions:getMarketingAnalytics,functions:exportRetargetingAudience --project influential-digital-2025
```

### Deploy Frontend (with Clarity)
```bash
firebase deploy --only hosting --project influential-digital-2025
```

### Set Facebook CAPI Token
```bash
firebase functions:secrets:set FB_ACCESS_TOKEN --project influential-digital-2025
# Paste token when prompted (starts with EAA...)

# Redeploy trackLead to pick up new secret
firebase deploy --only functions:trackLead --project influential-digital-2025
```

---

## Testing

### Test Lead Tracking
```bash
curl -X POST "https://us-central1-influential-digital-2025.cloudfunctions.net/trackLead" \
  -H "Content-Type: application/json" \
  -d '{
    "businessName": "Test Clinic",
    "email": "test@example.com",
    "industry": "veterinary",
    "utm_source": "facebook",
    "utm_campaign": "test-campaign"
  }'
```

Expected Response:
```json
{
  "success": true,
  "leadId": "abc123",
  "score": 55,
  "grade": "C"
}
```

### Test Event Tracking
```bash
curl -X POST "https://us-central1-influential-digital-2025.cloudfunctions.net/trackEvent" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "pageview",
    "page": "/vets",
    "utm_source": "google"
  }'
```

### Test Marketing Analytics
```bash
curl "https://us-central1-influential-digital-2025.cloudfunctions.net/getMarketingAnalytics" \
  -H "Authorization: Bearer aiva2025admin"
```

### Verify Facebook Pixel
1. Install Facebook Pixel Helper Chrome extension
2. Visit https://aiva.help
3. Should see: PageView event
4. Submit form: Should see Lead event

### Verify Clarity
1. Visit https://clarity.microsoft.com/projects
2. Check for "qf8j4qwo8l" project
3. Should see recordings within 24 hours

---

## Troubleshooting

### No Lead conversions in AdEspresso
1. Check if `fbq('track', 'Lead')` fires (browser console)
2. Verify FB_ACCESS_TOKEN is set for CAPI
3. Check Firebase function logs for CAPI errors

### UTM parameters not persisting
1. Check localStorage in browser DevTools
2. Look for `aiva_utm_*` keys
3. Verify aiva-tracker.js is loading

### Lead score always 0
1. Check if calculateLeadScore function receives data
2. Verify industry field is populated
3. Check Firebase function logs

### View Logs
```bash
firebase functions:log --only trackLead -n 50 --project influential-digital-2025
```

---

## Current Status

### Deployed & Working
- [x] GTM (GTM-PBXJ52FC) - All pages
- [x] Facebook Pixel (1098204243523075) - All pages
- [x] FB Lead event on form submit
- [x] Microsoft Clarity (qf8j4qwo8l) - All pages
- [x] aiva-tracker.js - UTM persistence
- [x] trackEvent function
- [x] trackLead function with scoring
- [x] getMarketingAnalytics function
- [x] exportRetargetingAudience function
- [x] Story Crafting System
- [x] Admin Dashboard Marketing tab

### Pending
- [ ] Facebook CAPI token (user action required)
- [ ] Automated email sequences (GHL integration)
- [ ] A/B test variants

---

**Last Updated**: 2025-12-03
**Version**: 1.0.0
**Author**: Claude Code
