# Google Workspace Infrastructure

## Overview

All Hardcard ecosystem email domains are managed through a single Google Workspace account.

## Domain Structure

| Domain | Type | Status |
|--------|------|--------|
| **rhizosciences.com** | Primary Domain | Active |
| aiva.help | User Alias | Gmail Activated |
| hempex.com | User Alias | Gmail Activated |
| vetsorcery.com | User Alias | Gmail Activated |
| hardcard.ai | User Alias | Gmail Activated |
| hardcard.app | User Alias | Gmail Activated |
| hardcard.org | User Alias | Gmail Activated |
| hardcard.world | User Alias | Gmail Activated |
| macagent.pro | User Alias | Gmail Activated |
| rhizosciences.co | User Alias | Gmail Activated |
| rhizosciences.com.au | User Alias | Gmail Activated |

## Email Configuration

### SMTP Credentials (for Firebase Functions)

```yaml
EMAIL_USER: dallas@rhizosciences.com
EMAIL_PASS: [App Password 'aiva' - 16 characters]
SMTP_SERVICE: gmail
```

### App Password Management

App passwords must be generated from the **primary domain account**:
1. Log in to https://myaccount.google.com as `dallas@rhizosciences.com`
2. Navigate to: Security → 2-Step Verification → App passwords
3. Create app password with descriptive name (e.g., "aiva", "vetsorcery")
4. Store in Firebase Secrets Manager

**Important:** App passwords for alias domains (like `mail@aiva.help`) will NOT work.
You must use the primary domain account (`dallas@rhizosciences.com`).

### Firebase Secrets

| Secret | Value | Version | Used By |
|--------|-------|---------|---------|
| EMAIL_USER | dallas@rhizosciences.com | 2 | trackLead, stripeWebhook, submitSetup |
| EMAIL_PASS | [App Password] | 4 | trackLead, stripeWebhook, submitSetup |

### Updating Credentials

```bash
# Update email user
echo "dallas@rhizosciences.com" | firebase functions:secrets:set EMAIL_USER --project influential-digital-2025 --data-file -

# Update app password (generate new one if expired)
echo "yourappasswordhere" | firebase functions:secrets:set EMAIL_PASS --project influential-digital-2025 --data-file -

# Redeploy affected functions
firebase deploy --only functions:trackLead,functions:stripeWebhook,functions:submitSetup --project influential-digital-2025
```

## Admin Consoles

| Console | URL | Purpose |
|---------|-----|---------|
| Google Workspace Admin | https://admin.google.com | Domain management, users, billing |
| Google Account Security | https://myaccount.google.com/security | 2FA, app passwords |
| App Passwords | https://myaccount.google.com/apppasswords | Generate app-specific passwords |

## Troubleshooting

### "Invalid login" Error

1. Verify you're using `dallas@rhizosciences.com` (not an alias)
2. Check app password is from the correct account
3. Ensure 2-Step Verification is enabled
4. Generate a new app password if needed

### Testing SMTP Connection

```javascript
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: 'dallas@rhizosciences.com',
    pass: 'yourappassword'
  }
});

transporter.verify((error, success) => {
  if (error) console.log('Failed:', error.message);
  else console.log('SMTP verified!');
});
```

---

*Last Updated: 2025-12-03*
*Verified Working: Yes*
