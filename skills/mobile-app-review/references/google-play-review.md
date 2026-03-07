# Google Play Store Review Guidelines — Deep Dive

Detailed reference for Google Play-specific review requirements. The main SKILL.md covers the actionable checklist — this file provides background, edge cases, and policy details.

## Google Play Policy Categories

Google organizes policies under these areas:

### Restricted Content
- Child sexual abuse material (CSAM) — zero tolerance
- Inappropriate content involving minors
- Hate speech, violence, bullying
- Terrorist content
- Dangerous organizations
- Marijuana, tobacco, alcohol — restricted by region
- Financial services — must be licensed where required
- Gambling — requires specific licensing
- Illegal activities — cannot facilitate

### Privacy, Deception & Device Abuse
- Must not deceive users about functionality
- No impersonation of other apps, companies, or entities
- Must not abuse device features (accessibility services, VPN, etc.)
- No unauthorized data collection or surveillance
- Data must be encrypted in transit

### Monetization & Ads
- Play Billing required for digital goods and subscriptions
- Physical goods can use external payment
- Ads must not interfere with app functionality
- Full-screen ads must be dismissible
- Ad content must be appropriate for app's content rating
- No deceptive ads that mimic system notifications

### Store Listing & Promotion
- Title, icon, screenshots must accurately represent the app
- No misleading claims or fake urgency
- No keyword stuffing in metadata
- User ratings and reviews cannot be manipulated
- Promotional materials must match app content

### Spam & Minimum Functionality
- Apps must provide lasting user value
- No apps that merely duplicate other apps
- No apps that exist solely to send traffic to a website
- Minimum functionality required — WebView wrappers usually rejected

## Data Safety Section — Detailed Requirements

The Data Safety form is **mandatory for all apps**. Google uses ML to cross-verify declarations against actual app behavior.

### Data Types to Declare

| Category | Examples |
|----------|---------|
| **Location** | Approximate, precise location |
| **Personal info** | Name, email, phone, address |
| **Financial info** | Payment info, purchase history |
| **Health & fitness** | Health data, fitness data |
| **Messages** | Emails, SMS, other messages |
| **Photos & videos** | Photos, videos |
| **Audio** | Voice recordings, music files |
| **Files & docs** | Documents, file metadata |
| **Calendar** | Calendar events |
| **Contacts** | Contact list |
| **App activity** | Page views, taps, search history |
| **Web browsing** | Browsing history |
| **App info & performance** | Crash logs, diagnostics, performance data |
| **Device identifiers** | Device ID, advertising ID |

### For Each Data Type Declare:
1. **Is it collected?** (data leaves the device)
2. **Is it shared?** (transferred to third parties)
3. **Is it required or optional?**
4. **Purpose**: App functionality, analytics, advertising, fraud prevention, etc.
5. **Is it processed ephemerally?** (not stored beyond the request)

### Common SDK Data Collection

Don't forget to declare data collected by your SDKs:

| SDK | Typically Collects |
|-----|-------------------|
| Firebase Analytics | App activity, device identifiers |
| Firebase Crashlytics | Crash logs, device info |
| Google Ads / AdMob | Device identifiers, app activity |
| Facebook SDK | Device identifiers, app activity |
| Sentry | Crash logs, device info |
| Amplitude / Mixpanel | App activity, device identifiers |
| Adapty / RevenueCat | Purchase history, device identifiers |
| OneSignal / FCM | Device identifiers (push token) |

## API Level Requirements

| Date | New Apps | App Updates |
|------|----------|-------------|
| **Aug 31, 2025** | API 35 (Android 15) | API 34 (Android 14) |
| **Prior** | API 34 | API 33 |

Apps not targeting the minimum API level:
- New submissions are rejected
- Existing apps become unavailable to new users on newer Android versions
- Existing installs continue to work

## Android App Bundle (.aab)

- **Required** for new app submissions (APK no longer accepted for new apps)
- Enables dynamic delivery (smaller downloads)
- Google Play generates optimized APKs per device
- Max download size: 200MB (base module); use asset packs for larger content

## Google Play Console Requirements

### Store Listing
- **App name**: Max 30 characters
- **Short description**: Max 80 characters
- **Full description**: Max 4000 characters
- **App icon**: 512×512px, 32-bit PNG
- **Feature graphic**: 1024×500px (required)
- **Screenshots**: Min 2, max 8 per device type (phone, tablet, TV, etc.)
- **Video**: Optional YouTube URL for promo video

### Content Rating
- IARC questionnaire must be completed
- Ratings applied automatically based on answers
- Inaccurate answers can lead to removal
- Re-rate if content significantly changes

### Financial Features Declaration (2025+)
- Required for **all apps** regardless of whether they have financial features
- Must be completed before any app update can be published
- Covers: payments, loans, crypto, trading, insurance, etc.

### Target Audience & Content
- Must declare target age groups
- If targeting children (<13), stricter requirements apply:
  - No personalized ads
  - Limited data collection
  - Teacher Approved program eligibility
  - Must comply with Families Policy

## 2025-2026 Policy Updates

### CSAE Policy (January 2026)
- All apps must have explicit content policies prohibiting CSAE
- In-app reporting mechanisms required
- Apps must act on reports promptly
- Applies to all apps, not just social/communication apps

### US Age Verification (January 2026)
- Some US states require age verification for certain app types
- Developers must implement verification mechanisms
- Affects dating, social media, alcohol, gambling apps

### SDK Attestations (2025+)
- Third-party SDK developers must provide attestations about data handling
- App developers must ensure their SDKs are compliant
- Google cross-checks SDK behavior with declared data practices

### Play Integrity API
- Replaces SafetyNet Attestation
- Verifies device integrity and app authenticity
- Recommended for apps with sensitive operations (payments, competitive gaming)

## Common Rejection Scenarios

### Metadata Rejection
- Title contains "best", "#1", or unverifiable superlatives
- Screenshots show features not in the app
- Description contains competitor names or trademarks
- Keyword stuffing in title or description

### Permission Rejection
- Requesting SMS permission without clear justification
- Requesting CALL_PHONE without a calling feature
- Background location without approved use case
- Accessibility service usage without disability-assistance purpose

### Payment Policy Violation
- Using Stripe/PayPal for digital goods instead of Play Billing
- Linking to external payment for subscriptions
- Not implementing Google Play Billing Library v5+

### Content Policy Violation
- Gambling features without proper licensing
- Health claims without medical verification
- Financial advice without appropriate disclaimers
- Real-money contests without age verification

## Review Timeline

- Most apps reviewed within **hours to 3 days**
- New developer accounts may face extended review (up to 7 days)
- Sensitive categories (finance, health, children) take longer
- Policy violation appeals via Play Console
- Escalation available through Google developer support

## Useful Links

- Play Console: https://play.google.com/console
- Policy Center: https://play.google.com/about/developer-content-policy/
- Data Safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Play Integrity: https://developer.android.com/google/play/integrity
