# Store privacy forms — App Store "App Privacy" and Google Play "Data safety"

> **DRAFT — needs legal/compliance review before filing.** Derived from the
> code in build 1.0.0+2 (25 Sep 2026). It supersedes
> `docs/STORE_LISTING_DATA.md`, which predates account deletion, medicine
> photos in the cloud, vitals, stock and the family subscription. Anything
> that depends on a contract or an account setting is **[CONFIRM]**, not a
> guess — a wrong answer on these forms is a compliance problem.

## 0. Facts the answers rest on (from the code)

| Fact | Where it is enforced |
|---|---|
| No ads, no analytics SDK, no crash-reporting SDK, no tracking, no data broker | `pubspec.yaml` has none of them |
| No account is needed; nothing is uploaded until the patient links a follower/nurse | `SyncService.push` is a no-op unless signed in **and** linked |
| Accounts are anonymous Supabase users — no email, no phone number | `AnonymousAuthService` (debt 2: must become Google/Apple before release) |
| Emergency contacts, sex, age, pharmacy number never leave the phone | `health_file_sync_guard_test`; no cloud columns |
| Paper photos leave the phone only if the patient enables sharing with the nurse; medicine photos are uploaded once linked | `PaperShareService`, `MedPhotoSync` (0026, 0029) |
| Scan photos go **directly from the phone to Google Gemini** (the C2 server route was reverted on 18 Sep 2026) | `GeminiPrescriptionReader.generate` — *the brief said "via our server"; that is not what the code does* |
| The follower/nurse push contains the patient name and medicine name | `supabase/functions/escalate/index.ts` → `notificationText` |
| Location is rounded to ~110 m on the device and sent only on the nearby screen | `NearbyPlaces` (3-decimal rounding) |
| In-app account deletion exists | Settings → «امسح حسابي» → `delete-account` Edge Function (0033) |
| All traffic is HTTPS | Supabase, Gemini, FCM, Overpass, OSM tiles, stores |

---

## 1. Apple — App Privacy

**Data used to track you: No.** (No cross-app/website tracking, no data
brokers, no ad networks.)

### Data linked to you

For every row below: **Purpose = App Functionality**. No row is used for
Third-Party Advertising, Developer's Advertising, Analytics, Product
Personalisation or Other Purposes.

| Apple category → type | Collected? | Why / notes |
|---|---|---|
| **Health & Fitness → Health** | Yes | Medicines, doses, schedules, lab results, glucose and other measurements, visits, emergency profile (blood type, allergies, conditions). Uploaded only after linking. |
| **Contact Info → Name** | Yes | Patient first name; follower/nurse display name. |
| **Contact Info → Email / Phone** | **No** | Anonymous accounts. Emergency phone numbers stay on the device. [CONFIRM when Google/Apple sign-in replaces anonymous auth — email may then be collected] |
| **User Content → Photos or Videos** | Yes | Medicine photos (cloud once linked); paper photos only if shared with the nurse; scan photos sent to Google Gemini for processing. |
| **User Content → Other User Content** | Yes | Notes, instructions, questions for the doctor. |
| **Identifiers → User ID** | Yes | Supabase account ID, patient UUID. |
| **Identifiers → Device ID** | Yes | Install ID in device health; push token. |
| **Purchases → Purchase History** | Yes | Family-subscription state (store, product, expiry, purchaser). |
| **Diagnostics → Other Diagnostic Data** | Yes | Device health codes (app/OS version, permission and battery state, reminder coverage). No crash logs. |
| **Location → Coarse Location** | **Not collected** (answer "No") — [CONFIRM] | Rounded location is sent to Apple Maps / OpenStreetMap only to answer the search in real time and is not stored by us. Apple's definition of "collect" excludes data used only to service a request in real time. Conservative alternative: declare Coarse Location, App Functionality, not linked. |
| Financial info, Contacts, Browsing/Search history, Sensitive info (other than health), Usage data, Audio | No | — |

### Account deletion (App Store Review Guideline 5.1.1(v))

In-app: Settings → «امسح حسابي» (patient, follower and nurse). Deletes the
account and its server data, not just deactivates it. Store subscriptions are
cancelled by the user in Apple settings — the screen says so.

---

## 2. Google Play — Data safety

**Does your app collect or share any of the required user data types?** Yes.
**Is all user data encrypted in transit?** Yes (HTTPS everywhere).
**Do you provide a way for users to request that their data be deleted?** Yes —
in-app, plus a web link: **[ACCOUNT_DELETION_URL] (required by Play; must be a
public page explaining how to delete, and how to request deletion without the
app)**.

"Shared" in Play's sense excludes service providers processing on our behalf
(Supabase, Firebase, Google Gemini as our API processor) and user-initiated
transfers the user expects (maps search, WhatsApp, dialer).

| Play category → type | Collected | Shared | Ephemeral | Required / optional | Purpose |
|---|---|---|---|---|---|
| Personal info → Name | Yes | No | No | Optional (only when linking) | App functionality, Account management |
| Personal info → User IDs | Yes | No | No | Optional | App functionality, Account management |
| Health and fitness → Health info | Yes | No | No | Optional (cloud copy only when linking) | App functionality |
| Photos and videos → Photos | Yes | No* | Scan photos: yes | Optional | App functionality |
| Location → Approximate location | Yes | No (user-initiated search) | **Yes** — not stored | Optional | App functionality |
| Financial info → Purchase history | Yes | No | No | Optional | App functionality |
| App info and performance → Diagnostics | Yes | No | No | Required once linked | App functionality |
| Device or other IDs | Yes | No | No | Optional | App functionality (push delivery) |
| Messages, Contacts, Calendar, Audio, Files and docs, Web browsing, App activity | No | — | — | — | — |

\* **[CONFIRM]** Scan photos are sent to Google's Gemini API. If the company's
Gemini terms let Google retain or use the images beyond processing our request,
this must be declared as **shared** and disclosed in the privacy policy. This
is the most consequential open item.

---

## 3. Open items before filing (both stores)

1. **Gemini retention/use terms** for the company account (see above).
2. **[SUPABASE_REGION]** — where the project runs; whether Egyptian users'
   health data crossing borders needs disclosure or consent under Law 151/2020.
3. **Backup and log retention** on the Supabase plan (privacy policy §4).
4. **[COMPANY_NAME], [COMPANY_EMAIL], [PRIVACY_URL], [TERMS_URL],
   [ACCOUNT_DELETION_URL]** — the app reads the two URLs from
   `--dart-define=PRIVACY_URL=… --dart-define=TERMS_URL=…`
   (`lib/core/legal/legal_links.dart`). Until they are set, the links in the
   app open nothing.
5. **Anonymous auth must be replaced** (debt 2) — the answers change if email
   becomes an account identifier.
6. **The Gemini key is inside the binary** (debt 2b) — store submission is
   forbidden until C2 is re-applied; that also changes the "directly to
   Google" line to "through our server".
7. **Age rating**: target audience is adults; the policy says not directed at
   children under [16]. Choose the store age rating accordingly.
8. **`0033_delete_account.sql` and the `delete-account` Edge Function must be
   deployed** before the deletion answers are true on the live project.
