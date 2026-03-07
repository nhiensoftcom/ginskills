# Apple App Store Review Guidelines — Deep Dive

Detailed reference for Apple-specific review requirements. The main SKILL.md covers the actionable checklist — this file provides background, edge cases, and policy details.

## Apple's Five Review Categories

Apple organizes its guidelines into five pillars:

### 1. Safety
- Apps must not include objectionable, offensive, or harmful content
- User-generated content requires moderation tools
- Physical harm risks must be mitigated
- Apps dealing with regulated goods (alcohol, tobacco, gambling) need age gating

### 2. Performance
- Apps must be complete and fully functional at submission
- Beta, demo, trial, or test versions are rejected
- Apps must work without modification on the current shipping OS version
- Hardware compatibility must be declared accurately

### 3. Business
- In-app purchases for digital goods must use Apple IAP
- "Reader" apps (Spotify, Netflix) may link to external sign-up but cannot prompt in-app purchase
- Commission: 30% standard, 15% for Small Business Program (<$1M/year)
- Subscriptions must auto-renew through Apple's system
- Free apps cannot become paid; must use IAP for upgrades

### 4. Design
- Apps must follow Human Interface Guidelines spirit (not pixel-perfect, but good UX)
- No custom UI that mimics iOS system dialogs
- Must support the latest device form factors
- App extensions and widgets must follow their specific guidelines
- Accessibility should be considered (VoiceOver, Dynamic Type)

### 5. Legal
- Apps must comply with all applicable laws in territories where available
- Privacy policy is mandatory
- Data collection must be disclosed via App Privacy Labels
- GDPR, CCPA, and other regional privacy laws must be respected
- Developer must hold necessary licenses for regulated industries

## Guideline Numbers That Matter Most

| Guideline | Topic | Common Issue |
|-----------|-------|-------------|
| **1.2** | User-Generated Content | Missing report/block/filter mechanisms |
| **2.1** | App Completeness | Crashes, bugs, blank screens |
| **2.3** | Accurate Metadata | Screenshots don't match app, misleading descriptions |
| **2.5.1** | Software Requirements | Using private APIs |
| **3.1.1** | In-App Purchase | Digital goods not using IAP |
| **3.1.2** | Subscriptions | Missing clear terms, no restore button |
| **4.0** | Design | Copycat apps, poor UI |
| **4.8** | Sign in with Apple | Missing when other social logins exist |
| **5.1** | Privacy | Missing policy, incorrect data labels |
| **5.1.1** | Data Collection | Undisclosed tracking or data sharing |
| **5.1.1(v)** | Account Deletion | No way to delete account from within app |

## App Store Connect Requirements

### App Information
- Primary language
- Bundle ID (cannot change after submission)
- SKU (your internal reference)
- Primary and secondary categories

### Pricing & Availability
- Price tier or custom pricing
- Territory availability
- Pre-order configuration (optional)

### App Privacy
- Privacy policy URL (required)
- App Privacy Labels questionnaire (all data types)

### Version Information
- What's New text
- Description, keywords, support URL
- Screenshots for each device type
- App icon (1024×1024, no alpha, no rounded corners)
- App Review Information: demo account, notes, contact

## Review Timeline & Appeals

- **90% of submissions** reviewed within 24 hours
- Rejections include specific guideline references
- **Appeal process**: Resolution Center in App Store Connect
- **Expedited review**: Available for critical bug fixes (use sparingly)
- **Guideline clarification**: Can request before building a feature

## 2025-2026 Policy Updates

### AI Disclosure (2025)
- Apps using external AI services must include consent modals
- Must specify the AI provider and data types shared
- User must be able to decline without losing core functionality

### Age Ratings (July 2025)
- New tiers: 13+, 16+, 18+
- Updated questionnaire must be completed by January 31, 2026
- Apps not updated risk submission delays

### SDK Requirements (April 2025+)
- All submissions must be built with SDKs for iOS 18
- Xcode 16+ required
- Check Apple Developer News for the latest requirements each spring

### Alternative App Marketplaces (EU)
- Applies to EU users under the Digital Markets Act
- Developers can opt into alternative distribution
- Separate notarization process for sideloaded apps

## Common Edge Cases

### WebView-Heavy Apps
Apple may reject apps that are essentially web wrappers. The app must provide native value beyond what a website offers. Hybrid apps (React Native, Flutter) are fine because they compile to native code.

### Subscription Gotchas
- Must clearly show: price, billing period, trial duration, cancellation terms
- "Start Free Trial" button must show what happens after the trial
- Introductory offers must not be misleading
- Management link: `https://apps.apple.com/account/subscriptions`

### Push Notifications
- Must not be used for advertising, promotions, or spam
- Users must be able to opt out
- Silent push is fine for background data sync
- Rich notifications should enhance, not replace, in-app content

### App Clips
- Must be under 15MB
- Cannot require sign-in for basic functionality
- Must link to the full app
