---
name: mobile-app-review
description: |
  **Mobile App Store Review Checklist**: Comprehensive pre-submission audit for Apple App Store and Google Play Store. Covers all review guidelines, common rejection reasons, and compliance requirements.
  - MANDATORY TRIGGERS: app store review, app review, store submission, submit app, app store checklist, apple review, google play review, app rejection, pass review, store guidelines, app compliance, publish app, release app, app store requirements, pre-submission
  - Use this skill whenever the user is preparing to submit or update a mobile app to the Apple App Store or Google Play Store, or when they want to audit their app against store guidelines. Also trigger when discussing app rejections, compliance issues, or store policy questions.
---

# Mobile App Store Review Checklist

A comprehensive, actionable checklist to pass Apple App Store and Google Play Store review. Covers both platforms with platform-specific callouts where they differ.

Use this skill to audit an app before submission, diagnose a rejection, or ensure ongoing compliance.

## How to Use This Skill

When the user asks for a review audit:

1. **Determine the target platform(s)** — iOS, Android, or both
2. **Identify the app type** — free, freemium, subscription, paid, contains UGC, uses AI, targets children, etc.
3. **Walk through each section below** as a checklist, checking the project's code and configuration
4. **Report findings** as PASS / FAIL / WARNING with specific file references and fix instructions
5. **Prioritize blockers** — items that will definitely cause rejection come first

---

## Phase 1: Instant Rejection Checks

These are the most common rejection reasons. Check these first — any failure here is a guaranteed rejection.

### 1.1 Crashes & Stability

- [ ] App launches without crashing on a fresh install
- [ ] All primary user flows complete without errors (signup, login, main feature, settings)
- [ ] No blank/white screens, infinite spinners, or dead-end states
- [ ] App handles no-network gracefully (show offline message, not crash)
- [ ] App handles expired auth tokens (redirect to login, not crash)
- [ ] Deep links and push notification opens don't crash
- [ ] Memory usage stays reasonable — no leaks on repeated navigation

**How to check**: Run the app on a real device (not just simulator). Walk through every screen. Toggle airplane mode mid-flow. Force-kill and reopen.

### 1.2 Incomplete or Placeholder Content

- [ ] No "Coming Soon", "TODO", "Lorem ipsum", or placeholder text anywhere
- [ ] No test/debug screens accessible to users
- [ ] No dead buttons or non-functional UI elements
- [ ] All navigation paths lead to real content
- [ ] No empty states without helpful messaging (e.g. "No items yet — tap + to add one")

### 1.3 Login & Demo Account

- [ ] If auth is required, provide a **demo account** in App Review Notes (Apple) / testing instructions (Google)
- [ ] Demo account works without 2FA, phone verification, or manual approval
- [ ] Demo account has enough data to showcase all features
- [ ] Social login (Apple, Google) works end-to-end
- [ ] **Apple Sign In is mandatory** if any third-party login is offered (Apple guideline 4.8)

---

## Phase 2: Privacy & Data

The #1 growing rejection category across both platforms.

### 2.1 Privacy Policy

- [ ] Privacy policy URL is set in App Store Connect / Google Play Console
- [ ] Privacy policy is accessible **inside the app** (usually Settings > Privacy Policy)
- [ ] Policy is hosted on a live, accessible URL (not localhost, not broken)
- [ ] Policy accurately describes all data collected, used, and shared
- [ ] Policy covers third-party SDKs (analytics, crash reporting, ads, AI services)

### 2.2 Data Collection Disclosure

**Apple (App Privacy Labels / "Nutrition Labels")**:
- [ ] All data types collected are declared in App Store Connect
- [ ] Declarations match actual app behavior and SDK data collection
- [ ] If using `expo-updates` or crash reporting, declare "Crash Data"
- [ ] If using analytics, declare "Analytics" and "Usage Data"

**Google (Data Safety Section)**:
- [ ] Data Safety form is complete in Play Console
- [ ] All data types and purposes are accurately declared
- [ ] SDK data collection is included (Google cross-checks with ML)
- [ ] Encryption in transit is declared if applicable

### 2.3 Permissions

- [ ] Only request permissions the app actually uses
- [ ] Permission prompts explain **why** the permission is needed (custom message, not default)
- [ ] Camera, microphone, location, photo library — each has a clear use case description
- [ ] Permissions are requested **in context** (when the user taps the relevant feature), not on first launch
- [ ] App functions gracefully when permissions are denied (degrade, don't crash)

**Platform-specific permission strings**:
- **iOS**: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSMicrophoneUsageDescription`, etc. — all must be human-readable and specific
- **Android**: Only declare permissions in `AndroidManifest.xml` that are actually used. Remove unused permissions added by third-party libraries

### 2.4 Account Deletion

- [ ] If the app has user accounts, there must be a way to **delete the account** from within the app
- [ ] Account deletion is accessible (Settings is the common location)
- [ ] Deletion actually removes user data (or clearly states the retention policy)
- [ ] Both Apple and Google now require this

### 2.5 AI & External Services (2025+ requirement)

- [ ] If the app sends user data to external AI services, show a **consent modal** before any data is shared
- [ ] Consent modal identifies the AI provider and data types being shared
- [ ] User can decline without losing core app functionality
- [ ] AI-generated content is labeled if applicable

### 2.6 Tracking & ATT (iOS only)

- [ ] If app tracks users across apps/websites, implement **App Tracking Transparency (ATT)** prompt
- [ ] ATT prompt must appear before any tracking begins
- [ ] App functions normally if user declines tracking

---

## Phase 3: In-App Purchases & Subscriptions

IAP issues are the #3 most common rejection reason on Apple.

### 3.1 Payment Rules

- [ ] **All digital goods/content** must use the platform's IAP system (Apple IAP / Google Play Billing)
- [ ] No links to external payment methods for digital goods
- [ ] Physical goods and services (e.g., ride-sharing, food delivery) can use external payment
- [ ] No language that directs users to purchase outside the app

### 3.2 Restore Purchases

- [ ] "Restore Purchases" button exists and is **easily findable** (Settings or Paywall screen)
- [ ] Restore works after: reinstall, new device, logout + login
- [ ] Restored purchases correctly unlock all entitled content
- [ ] **Test flow**: Purchase → Delete app → Reinstall → Restore → Verify unlocked

### 3.3 Subscription Requirements

- [ ] Subscription period is at least 7 days
- [ ] Pricing and renewal terms are clearly displayed **before** the purchase button
- [ ] Free trial terms are explicit (duration, what happens after, how to cancel)
- [ ] Subscription management is accessible (link to platform subscription settings)
- [ ] Cancellation flow is clear — no dark patterns

### 3.4 Paywall UI

- [ ] Price is displayed in the user's local currency (use platform APIs)
- [ ] All features gated by the paywall are clearly listed
- [ ] Free users can still use the core app experience
- [ ] No misleading "free" claims if a subscription is required for core functionality

---

## Phase 4: Content & Safety

### 4.1 Age Rating

- [ ] Age rating questionnaire is completed accurately
- [ ] Content matches the declared age rating
- [ ] **Apple (2025+)**: New age tiers — 13+, 16+, 18+. Updated questionnaire must be completed by January 31, 2026
- [ ] **Google**: Content rating questionnaire via IARC is completed
- [ ] If app targets minors, additional compliance is required (COPPA, Google CSAE policy)

### 4.2 User-Generated Content (UGC)

If users can create, upload, or share content:

- [ ] Content **reporting** mechanism exists (per-item report button)
- [ ] User **blocking** is available (server-side, not just local hide)
- [ ] Content **moderation** system is in place (filtering, review queue, or AI moderation)
- [ ] Published **contact info** for support is accessible in-app
- [ ] Terms of Service are accessible and prohibit objectionable content

### 4.3 Restricted Content

- [ ] No hate speech, violence, or illegal content
- [ ] No copyrighted material used without license
- [ ] No misleading health or financial claims
- [ ] Alcohol, gambling, dating, real-money contests — require additional compliance and age gating

---

## Phase 5: Design & UX

### 5.1 Apple Human Interface Guidelines

- [ ] App respects Safe Area insets (notch, Dynamic Island, home indicator)
- [ ] No custom UI that mimics system alerts or notifications
- [ ] Back navigation works consistently
- [ ] App respects system text size (Dynamic Type) — or at minimum doesn't break at larger sizes
- [ ] Dark mode is either fully supported or explicitly opted out
- [ ] App looks correct on all supported iPhone sizes (SE through Pro Max)
- [ ] If `supportsTablet` is not explicitly false, app must be usable on iPad

### 5.2 Google Material Design

- [ ] App handles back button/gesture correctly on Android
- [ ] Status bar and navigation bar are styled appropriately
- [ ] App works across different screen densities (mdpi through xxxhdpi)
- [ ] Edge-to-edge display is handled properly
- [ ] Keyboard doesn't cover input fields

### 5.3 Universal Requirements

- [ ] Loading states are present (skeletons, spinners) — no blank screens while data loads
- [ ] Error states provide helpful messages and recovery actions
- [ ] Empty states guide users on what to do next
- [ ] Text is readable (sufficient contrast, minimum ~14sp/pt body text)
- [ ] Touch targets are at least 44×44pt (iOS) / 48×48dp (Android)
- [ ] No horizontal scroll on screens that shouldn't scroll horizontally

---

## Phase 6: Metadata & Store Listing

### 6.1 App Icon

- [ ] **Apple**: 1024×1024px, no transparency, no rounded corners (system applies them), no alpha channel
- [ ] **Google**: 512×512px, 32-bit PNG with alpha channel allowed
- [ ] Icon is unique, recognizable, and not confusingly similar to existing apps

### 6.2 Screenshots

- [ ] Screenshots show **actual app UI** (not just marketing graphics with no app content)
- [ ] Required sizes provided for all targeted devices
- [ ] **Apple**: At least 1 screenshot per localization; up to 10 per device type
- [ ] **Google**: Minimum 2 screenshots; up to 8; 16:9 or 9:16 aspect ratio
- [ ] Screenshots are not misleading — features shown must exist in the app

### 6.3 Description & Keywords

- [ ] Description accurately reflects app functionality
- [ ] No competitor names or trademarked terms in keywords
- [ ] No claims like "#1 app" or "best" without verification
- [ ] **Google**: Title max 30 chars; short description max 80 chars
- [ ] Support URL and marketing URL are live and accessible

### 6.4 What's New / Release Notes

- [ ] Release notes describe actual changes (not just "bug fixes" repeatedly)
- [ ] No promotional language that doesn't match the update

---

## Phase 7: Technical Requirements

### 7.1 iOS-Specific

- [ ] Built with the **latest required Xcode and SDK** (currently iOS 18 SDK as of April 2025)
- [ ] 64-bit architecture support
- [ ] App does not use private/undocumented APIs
- [ ] No embedded web browser for core functionality (WebView-only apps get rejected)
- [ ] App binary is under 4GB (over-the-air download limit is 200MB on cellular)
- [ ] Background modes are only declared if actually used (audio, location, VOIP, etc.)

### 7.2 Android-Specific

- [ ] Target API level meets minimum requirement (API 35 / Android 15 for new apps as of Aug 2025)
- [ ] App bundle format (`.aab`) is used for new app submissions
- [ ] `minSdkVersion` is reasonable for your audience (API 24+ is common)
- [ ] No unnecessary permissions in `AndroidManifest.xml`
- [ ] ProGuard/R8 rules don't break runtime behavior
- [ ] **Financial features declaration** is completed in Play Console (required for all apps)

### 7.3 Both Platforms

- [ ] App size is optimized (large downloads reduce conversion)
- [ ] Network requests use HTTPS (no plain HTTP)
- [ ] API keys, secrets, and tokens are not hardcoded in the bundle
- [ ] No console.log / debug logging in production builds
- [ ] Push notifications work correctly (token registration, payload handling)
- [ ] Universal/deep links resolve correctly

---

## Phase 8: Pre-Submission Final Check

### The "Reviewer Run"

Perform this exactly as an app reviewer would:

1. **Fresh install** the app on a real device (not simulator)
2. **Create an account** (or use the demo account you'll provide)
3. **Complete the main user flow** — the primary thing your app does
4. **Test each tab/section** — tap every button, open every screen
5. **Toggle airplane mode** — verify offline handling
6. **Test restore purchases** — if applicable
7. **Find the privacy policy** — can you reach it in < 3 taps?
8. **Find account deletion** — can you reach it in < 3 taps?
9. **Force-kill and reopen** — does the app restore state correctly?
10. **Check all links** — support URL, privacy URL, terms URL

### Submission Notes

- **Apple App Review Notes**: Include demo credentials, instructions for features that need special setup, explanations for any permissions
- **Google Testing Instructions**: Same — provide credentials and context
- **Contact info**: Ensure your developer contact email is real and monitored
- **Response plan**: Have someone available to respond to reviewer questions within 24-48 hours

---

## Quick Reference: Top Rejection Reasons

| Rank | Apple | Google |
|------|-------|--------|
| 1 | Crashes / bugs (2.1) | Crashes / ANR |
| 2 | Inaccurate metadata (2.3) | Misleading metadata |
| 3 | IAP misconfiguration (3.1.1) | Privacy / Data Safety violations |
| 4 | Missing privacy policy | Missing privacy policy |
| 5 | Incomplete app | Permissions abuse |
| 6 | No account deletion | Intellectual property |
| 7 | Missing Apple Sign In | Restricted content |
| 8 | Broken links | Broken links / dead features |

## References

For detailed platform-specific checklists, see:
- `references/apple-review.md` — Full Apple App Store review guidelines deep-dive
- `references/google-play-review.md` — Full Google Play policy requirements deep-dive
