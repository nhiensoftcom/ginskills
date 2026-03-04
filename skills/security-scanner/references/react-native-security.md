# React Native Mobile Security Checklist

Deep-dive security checklist for the React Native mobile app. Aligned with **OWASP Mobile Top 10 2024**. Read this when scanning the mobile app.

## OWASP Mobile Top 10 Mapping

| OWASP ID | Risk | Primary Section |
|----------|------|-----------------|
| M1 | Improper Credential Usage | Secure Storage, Authentication Flow |
| M2 | Inadequate Supply Chain Security | Third-Party SDKs |
| M3 | Insecure Authentication/Authorization | Authentication Flow |
| M4 | Insufficient Input/Output Validation | Deep Links, Data Leakage |
| M5 | Insecure Communication | Network Security |
| M8 | Security Misconfiguration | Binary Protection |
| M9 | Insecure Data Storage | Secure Storage |
| M10 | Insufficient Cryptography | Secure Storage, Network Security |

## Table of Contents
1. [Secure Storage](#secure-storage) (M1, M9)
2. [Network Security](#network-security) (M5, M10)
3. [Authentication Flow](#authentication-flow) (M1, M3)
4. [Deep Links & URL Schemes](#deep-links--url-schemes) (M4)
5. [Binary Protection](#binary-protection) (M8)
6. [Data Leakage](#data-leakage) (M4)
7. [Third-Party SDKs](#third-party-sdks) (M2)
8. [Hermes Engine Security](#hermes-engine-security)

---

## Secure Storage

### Current Implementation (GOOD)
- File: `shared/libs/token-storage.ts`
- Uses `react-native-keychain` (Keychain on iOS, Keystore on Android)
- Separate service names for access and refresh tokens

### Checklist
- [ ] Tokens stored in Keychain/Keystore (NOT AsyncStorage) ✅ already done
- [ ] AsyncStorage only used for non-sensitive data (preferences, UI state)
- [ ] No sensitive data in `MMKV`, `SecureStore`, or custom solutions without encryption
- [ ] Biometric lock for sensitive operations (account deletion, payment)
- [ ] Data cleared on logout (tokens, cached user data)
- [ ] No sensitive data in app logs (check `console.log` in release builds)

### What NOT to store insecurely
```typescript
// BAD: AsyncStorage is NOT encrypted
import AsyncStorage from '@react-native-async-storage/async-storage';
await AsyncStorage.setItem('token', accessToken); // INSECURE

// GOOD: Keychain is encrypted by OS
import * as Keychain from 'react-native-keychain';
await Keychain.setGenericPassword('accessToken', token, {
  service: 'AppTokens',
});
```

## Network Security

### Certificate Pinning
- [ ] Certificate pinning implemented for production API
- [ ] Pinning includes backup certificates
- [ ] Pinning gracefully handles certificate rotation

### Network Checklist
- [ ] All API calls use HTTPS (no HTTP fallback)
- [ ] No `NSAppTransportSecurity` exceptions for production domains (iOS)
- [ ] `android:usesCleartextTraffic="false"` in AndroidManifest
- [ ] API base URL loaded from config, not hardcoded
- [ ] Proxy detection (optional — detect MITM tools like Charles/Fiddler)
- [ ] Sensitive headers not logged in development interceptors

### Check in API Client
```typescript
// File: shared/libs/api-client.ts
// Verify:
// 1. Base URL is HTTPS
// 2. Token not logged in request interceptor
// 3. Error interceptor doesn't leak tokens in error messages
```

## Authentication Flow

### Token Refresh Pattern (Current — GOOD)
- Single-flight refresh prevents race conditions
- 401 responses trigger automatic refresh
- Failed refresh → logout and clear tokens

### Checklist
- [ ] Access token refreshed silently before expiry
- [ ] Refresh token rotation (new refresh token on each use)
- [ ] Failed refresh clears all auth state
- [ ] Login screen shown immediately on auth failure (no stale UI)
- [ ] Biometric re-authentication for sensitive actions
- [ ] Session timeout after inactivity

### Background State
- [ ] App clears sensitive data from memory when backgrounded
- [ ] Screenshot prevention on sensitive screens (iOS: `UIApplicationDelegate`, Android: `FLAG_SECURE`)
- [ ] Clipboard cleared after copying sensitive data (if applicable)

## Deep Links & URL Schemes

### Checklist
- [ ] Deep link URLs validated before navigation
- [ ] No sensitive data in deep link parameters
- [ ] Deep link handlers sanitize all parameters
- [ ] Custom URL scheme can't be hijacked (use Universal Links / App Links)
- [ ] OAuth redirect URIs validated against whitelist

### Vulnerability Pattern
```typescript
// BAD: Unvalidated deep link navigation
Linking.addEventListener('url', ({ url }) => {
  navigation.navigate(url.split('/').pop()); // Attacker controls destination
});

// GOOD: Validate against known routes
const ALLOWED_ROUTES = ['wardrobe', 'outfit', 'settings'];
Linking.addEventListener('url', ({ url }) => {
  const route = parseRoute(url);
  if (ALLOWED_ROUTES.includes(route.name)) {
    navigation.navigate(route.name, route.params);
  }
});
```

## Binary Protection

### Checklist
- [ ] ProGuard/R8 obfuscation enabled (Android release)
- [ ] Hermes bytecode compilation (reduces reverse engineering)
- [ ] No debug flags in release builds
- [ ] No sensitive strings in binary (use env vars or remote config)
- [ ] Root/jailbreak detection (optional, but recommended for financial features)
- [ ] Tamper detection (optional)

### Expo/EAS Build
- [ ] `expo-updates` configured with code signing
- [ ] OTA updates use HTTPS
- [ ] Update manifest signed to prevent MITM

## Data Leakage

### Checklist
- [ ] No sensitive data in `console.log` (strip in production with babel plugin)
- [ ] No sensitive data in crash reports (Sentry, Crashlytics)
- [ ] Keyboard caching disabled on sensitive inputs (`secureTextEntry`, `autoCorrect={false}`)
- [ ] WebView content not cached (if WebView used)
- [ ] Images with PII not cached to disk unencrypted
- [ ] Clipboard data cleared after sensitive copy operations

### Production Logging
```javascript
// babel.config.js — strip console in production
module.exports = {
  plugins: [
    ['transform-remove-console', { exclude: ['error', 'warn'] }],
  ],
};
```

## Third-Party SDKs

### Checklist
- [ ] SDKs reviewed for data collection practices
- [ ] Minimal permissions requested
- [ ] Analytics SDKs don't collect PII without consent
- [ ] Adapty SDK (subscriptions) — ensure payment data handled securely
- [ ] Expo modules — check for known vulnerabilities

### Data Flow Review
Map where user data flows:
1. User input → App → Backend API (encrypted in transit?)
2. User input → App → Analytics SDK (what's collected?)
3. User input → App → LLM API (PII in prompts?)
4. User photos → App → Image generation API (stored? for how long?)

### Supply Chain Scanning (OWASP M2)
- [ ] `npm audit` / `yarn audit` run regularly on the mobile app directory
- [ ] Native dependency versions checked for known CVEs
- [ ] Expo SDK version up to date
- [ ] No deprecated or unmaintained RN packages

## Hermes Engine Security

React Native uses the Hermes JS engine (from Facebook/Meta). Key considerations:

### Checklist
- [ ] Hermes bytecode compilation enabled for release builds (harder to reverse-engineer than plain JS)
- [ ] Hermes version updated — check for known Hermes vulnerabilities
- [ ] No eval-like patterns that could be exploited through the JS engine
- [ ] Source maps NOT included in release builds (would expose original code)

### Threat Model
- Native JS engines make extracting minified JS from app bundles easy
- Hermes compiles to bytecode which is harder to decompile but NOT impossible
- Hermes has had several reported vulnerabilities — keep it updated
- Application logic in the entry file is visible; protect sensitive business logic server-side
