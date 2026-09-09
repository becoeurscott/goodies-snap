# goodiesSnap — App Store Submission Guide & Checklist

Bundle ID: `com.goodies.goodiesSnap` · Apple App ID: `6804307648`
Last audited against code + backend: **2026-09-08**

Legend: ✅ done/verified · ⚠️ blocked on you (Claude can't do it) · 🐞 must-fix bug · ⬜ not started

---

## 0. How to read this
Everything below is either **verified in code/backend** or **explicitly flagged as owed**.
Do not submit until every item in Section 8 (Final gate) is ✅. The items that will get you
**rejected** (not just warned) are marked **[REJECT-RISK]**.

---

## 1. What goodiesSnap is (the pitch for App Review + the listing)
A native SwiftUI recipe app. Users capture recipes by photo/link/text (AI extraction),
browse a 793-recipe Discover catalog, build recipe-grouped shopping lists with **real Kroger
store prices**, cook in step mode, plan meals, and share in a moderated community. Paid tiers
(Plus/Pro) raise a metered AI-action quota.

Key facts App Review will test:
- User-generated content (community) → needs moderation + blocking + reporting → **age 17+**.
- AI features → make no medical/allergy guarantees (disclaimer already in Terms).
- Subscriptions → StoreKit 2, server-verified.

---

## 2. Legal & privacy — [REJECT-RISK]
- ✅ Terms of Use + Privacy Policy written and deployed → https://j7pth4qn.insforge.site
- ✅ App links (Legal.swift) point to the live pages — old `goodiessnap.app` links were dead.
- ✅ `PrivacyInfo.xcprivacy` bundled (email/name/userID/photos/user content; all linked; no
  tracking; UserDefaults reason CA92.1).
- ✅ `ITSAppUsesNonExemptEncryption = false` in Info.plist.
- ⚠️ **Fill legal placeholders** in Terms/Privacy: legal entity name, registered address,
  governing law, `legal@`/`privacy@` addresses. Drafts need a lawyer's review.
- ⚠️ **Support email must exist.** Pages use `support@goodiessnap.app`, which does **not**
  exist. Create a real mailbox (App Review emails it). Do not publish a personal address
  without deciding to.
- ⬜ In App Store Connect: set **Privacy Policy URL** and **Support URL** to live pages.
- ⬜ Complete the **App Privacy "nutrition label"** questionnaire — must match
  `PrivacyInfo.xcprivacy` (email, name, user ID, photos, user content; linked; no tracking).

---

## 3. Account, moderation & UGC — [REJECT-RISK]
These clear the two guaranteed UGC rejections (5.1.1(v) deletion, 1.2 moderation).
- ✅ **In-app account deletion** — Profile → Account → typed-DELETE sheet; edge fn `account`
  cascades all user data. Verified end to end.
- ✅ **Block** (both directions), **Report**, auto-hide at 3 reporters — RLS-enforced,
  verified with throwaway accounts.
- ✅ **EULA checkbox gates Create Account** (AuthView).
- ⬜ **A way to action reports.** Today reports are SQL-only; there is no moderator queue UI.
  App Review expects the *mechanism* (report/block) which exists — but you need an operational
  plan to read `content_reports` and act within 24h. Document it or build a minimal admin read.

---

## 4. In-App Purchases / subscriptions — [REJECT-RISK]
- ✅ StoreKit 2 (`Purchases.swift`), server JWS verification against pinned Apple Root CA G3,
  restore + `currentEntitlements` sync. Client can't self-grant plan (403 verified).
- ✅ `APP_APPLE_ID = 6804307648` secret set → **Production** receipts verify (done 2026-09-07).
- ✅ Paywall shows Terms + Privacy links and subscription terms (3.1.2).
- ✅ **Intro-offer misrepresentation fixed** — `Promo.introOfferAvailable = false`; paywall
  now shows honest full price (was: advertised "first month $4.99" with no StoreKit offer →
  real charge $9.99). 🐞→✅
- ⚠️ In **App Store Connect** (only you):
  - Create/confirm the 4 products with EXACT ids:
    `com.goodies.goodiesSnap.plus.monthly`, `.plus.yearly`, `.pro.monthly`, `.pro.yearly`.
  - **Paid Apps agreement active** + each product **"Ready to Submit"** (else they won't load).
  - Add the 4 products **to this app version** for review.
  - Fill each subscription's localization, review screenshot, and pricing.
- ⬜ If you want the $4.99 promo back: add a real StoreKit **Introductory Offer** (Pay As You
  Go, 1 mo, $4.99) to plus.monthly/pro.monthly, mirror in `Products.storekit`, then flip the
  flag true. The action-capped in-app "Try Pro 7 days" is NOT StoreKit-billed and stays on.

---

## 5. Backend / server config — [REJECT-RISK for AI]
Without these, core features 503 during review → functional-bug rejection (2.1).
- ⚠️ **`OPENROUTER_API_KEY` secret NOT set** → every AI call (extract/scan/recipe-for-dish)
  returns 503. **Set it before submission** or App Review hits dead AI features.
- ✅ AI is fully server-metered (edge fn `ai`), refunds on model failure. Free 5 / Plus 100 /
  Pro 400 / trial 25.
- ✅ Kroger pricing LIVE (approved; `prices` fn deployed; real prices verified). ⚠️ **Rotate
  KROGER_CLIENT_SECRET** — it was pasted in plaintext during setup. US Kroger stores only
  (message the limitation in-UI; non-US users get no matches).
- ⚠️ **SMTP + email verification.** `require_email_verification` is OFF. Only flip it ON
  **after** SMTP credentials exist, or new signups get locked out.
- ✅ Dev provider key / direct `api.anthropic.com` path are `#if DEBUG` only — confirmed by
  `strings` on Release: zero `anthropic`/`gs_api_key` hits. (Re-verify after any build.)

---

## 6. Content licensing — [REJECT-RISK 5.2.1 / 2.1]
- ⚠️ **TheMealDB**: Discover's 793 recipes were seeded with test key "1" (dev/educational
  only). Public release needs a **paid supporter key** — re-run
  `scripts/import-catalog.mjs` with `MEALDB_KEY=<supporter>`. Attribution already shown.
- ⚠️ **Unsplash + TheMealDB images are hotlinked** (38 Unsplash seeds + catalog images).
  Risk: 2.1 if CDN slow during review; 5.2.1 on rights. Prefer bundling/licensing art, or at
  minimum confirm rights + CDN reliability.

---

## 7. Build, metadata & assets
- ✅ App icon: mark-based (no wordmark), 1024², no alpha, dark + tinted variants.
- ⚠️ **Keep DerivedData OUT of the iCloud-synced Desktop** — iCloud taints the bundle and
  breaks codesign. Build with DerivedData in a non-synced path.
- ⬜ Set **Release** build config; bump **version** (e.g. 1.0.0) + **build** number.
- ⬜ Archive → validate → upload via Xcode Organizer (or Transporter).
- ⬜ **Screenshots** for required device sizes (6.7" + 6.5" + 5.5" if supported, iPad if
  universal). Use the headless recipe (`-gsScreen home|library|import|shopping|plan|feed`).
- ⬜ **Description, keywords, subtitle, promo text, category** (Food & Drink).
- ⬜ **Age rating: 17+** (UGC + unrestricted web/community). Answer the questionnaire honestly.
- ⬜ **App Review notes**: explain AI capture, community moderation, how to reach paywall, and
  provide a **demo account** (test: `testcook1@example.com` / `Passw0rd!123`) + note that
  IAP is server-verified.
- ⬜ **Export compliance**: declare non-exempt encryption = false (matches Info.plist).

---

## 8. FINAL GATE — verify each before hitting Submit
Do not submit until all are ✅.

**Will reject if missing**
- [ ] `OPENROUTER_API_KEY` set; AI extract/scan tested from a real device (not 503).
- [ ] 4 IAP products "Ready to Submit", attached to the version, load in the paywall.
- [ ] Paid Apps agreement active.
- [ ] Privacy Policy URL + Support URL live and reachable in App Store Connect.
- [ ] Support mailbox actually receives mail.
- [ ] Account deletion works from a fresh signed-in account (typed DELETE).
- [ ] Report + block verified in the live build.
- [ ] TheMealDB supporter key in use (or Discover disabled for launch).
- [ ] Image rights + CDN reliability confirmed (or images bundled).
- [ ] Legal placeholder fields filled + reviewed.
- [ ] App Privacy questionnaire matches `PrivacyInfo.xcprivacy`.
- [ ] Age rating 17+.

**Should verify (functional pass)**
- [ ] Release binary: `strings` shows no `anthropic`/`gs_api_key`.
- [ ] Intro-offer flag false → paywall shows honest full price.
- [ ] Kroger secret rotated; prices load for a US ZIP; graceful message for non-US.
- [ ] SMTP set before flipping `require_email_verification` (or leave OFF).
- [ ] Demo account + review notes filled.
- [ ] Onboarding, import (photo/link/text), cook mode, shopping, community composer all
      tested by hand on device (some flows were only headless-verified).
- [ ] Version/build bumped; archive validates clean.

---

## 9. Who does what
**Only you (Apple/portal/legal):** IAP products + agreement, App Store Connect metadata &
privacy questionnaire, screenshots upload, TheMealDB supporter key purchase, image licensing,
support mailbox, legal review, SMTP credentials, secret rotation, final Submit.

**Claude can help with:** re-running the catalog importer, wiring a minimal moderator read,
generating screenshots via the headless recipe, drafting listing copy/description, filling
legal placeholder text, verifying the Release binary, and building/archiving locally.

Say the word on any ⚠️/⬜ item and I'll take the next step.
