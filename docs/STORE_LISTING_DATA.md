> **Superseded (25 Sep 2026) by `docs/legal/store_forms.md`**, which reflects
> account deletion, medicine photos, vitals, stock and the family subscription.
> Kept for history.

# Store listing — data collection draft

Input for **Apple's App Privacy labels** and **Google Play's Data Safety**
form. Written from the code, not from intent.

**This is a draft for review, not a filed answer.** Anything that depends on a
contract, an account tier or a company decision is marked **TODO** rather than
guessed — a wrong answer on these forms is a compliance problem, and a
plausible-looking guess is worse than a blank.

Blockers referenced below are defined in `HANDOVER.md` §5.

---

## 1. The short version

The app is a medication reminder for elderly patients. It handles **health
data**, and a linked caregiver can read most of it. There are **no ads, no
analytics SDK, no crash reporting, and no tracking** — nothing in the app
profiles a user or shares data with a data broker.

For Apple's "Data used to track you": **No.**

---

## 2. What is collected

"Cloud" means Supabase (project `uyhelimwadgxhecnfumo`). Data only reaches the
cloud if the patient links a caregiver; with no link, the app is fully local
and works offline forever.

| Data | Examples | On device | In cloud | Purpose |
|---|---|---|---|---|
| Health — medications | Name, amount, active ingredient, notes, start/stop | yes | yes | Core function: scheduling reminders |
| Health — doses | Scheduled time, taken / missed / skipped | yes | yes | Reminders, and the caregiver's view |
| Health — lab results | Test name, value, unit, the report's own printed range | yes | yes | Health file |
| Health — glucose readings | Value (mg/dL), context (fasting / after eating), time | yes | yes | Health file |
| Health — records | Visits, prescriptions, imaging, bookings: title, date, doctor, place, notes | yes | yes | Health file |
| Health — follow-ups | Stage and appointment dates for a lab or visit | yes | yes | Appointment reminders |
| Health — emergency profile | Blood type, allergies, chronic conditions | yes | yes | Emergency card |
| **Emergency contacts** | Name, phone number, relation | yes | **no** | Emergency card. **Deliberately never synced** — the cloud has no column for them, enforced by a test |
| **Prescription / lab photos** | Camera or gallery images | yes | **no** | Read by AI, then kept as the record's paper. Never uploaded to our servers; see §3 for Google |
| Personal — name | Patient's first name; caregiver's display name and relation | yes | yes | Greeting; telling the patient who follows him |
| Personal — sex, age | Optional; age may be left blank | yes | **no** | Wording only ("بتفطر"/"بتفطري"). Local-only |
| Daily routine | Wake, meals, sleep times | yes | yes | Every reminder is an anchor + offset, not a clock time |
| Location — approximate | Rounded to 3 decimals (~110 m) **before leaving the device** | not stored | **no** | Finding nearby pharmacies, doctors, hospitals, labs |
| Device — push token | FCM registration token | yes | yes | Delivering the caregiver's missed-dose alert |
| Device — diagnostics | App version, platform, OS version, timezone, notification permission, battery-optimisation state, pending-reminder count, install id | yes | yes | Self-check: detecting phones where reminders have silently stopped. **Safety codes only — no medical content** |
| Identifiers | Supabase user id, patient uuid, install id, FCM token | yes | yes | Linking a caregiver; addressing a push |

### Not collected at all

No contacts list (the picker returns one contact, chosen by the user, out of
process — no permission is requested). No microphone, no speech. No advertising
ID. No browsing history. No payment data — payments are not built (B7).

---

## 3. Third parties that receive data

| Party | What reaches them | When | Notes |
|---|---|---|---|
| **Supabase** | Everything in the "in cloud" column | Only after a caregiver is linked | Processor. Company-owned project. |
| **Google — Gemini API** | **The prescription / lab / medicine-box photo itself**, plus the prompt | Each time the user taps to scan | The image is health data and it leaves the device. See the TODO below on retention. |
| **Google — Firebase Cloud Messaging** | Push token, and **the alert text, which contains the patient's name and the medication name in plaintext** | Each caregiver escalation | Health data transits FCM. Unavoidable for push, but must be declared. |
| **Apple — APNs** | Same alert text, once iOS push exists (B3) | Not active yet | |
| **OpenStreetMap (Overpass + tiles)** | Approximate location, rounded to ~110 m | Android only, when the user opens "القريب مني" | Public instances today — see B9 |
| **Apple Maps (MapKit)** | Approximate location | iOS only, same screen | Runs in the OS, under Apple's own terms |
| **Apple Maps / geo: links** | The destination the user picked | When the user taps "الطريق" | Hand-off to the maps app |

The app tells the user, on screen, that their approximate location is sent and
to whom.

---

## 4. Encryption

| | State |
|---|---|
| In transit | **Yes, everywhere.** All endpoints are HTTPS (Supabase, Gemini, FCM, Overpass, OSM tiles). No cleartext traffic. |
| At rest — device | **Not separately encrypted.** The SQLite database and the photos rely on the OS's own device encryption (iOS Data Protection, Android FBE). No SQLCipher. |
| At rest — cloud | Supabase platform default (Postgres disk encryption). **TODO:** confirm what the company's Supabase plan guarantees and whether that satisfies the answer both stores expect. |

---

## 5. Deletion — how it works today

| Thing | Today |
|---|---|
| A record (lab, visit, prescription…) | Deleted on confirmation: content cleared on device, the attached photo deleted, and the cloud row upserted as a tombstone then deleted on the next push. A daily cron is the backstop for a phone that never comes back online. |
| A medication | **Soft** — removed from every list, past history kept. Never hard-deleted, because sync only upserts and a deleted local row would leave a ghost dose alerting the caregiver. |
| A caregiver link | Sign-out clears the push token first, then the session. |
| **The account and all its data** | **Not built — blocker B4.** There is no in-app path to delete an account. Both stores require one for any app that creates accounts. |

**This is the single biggest gap for a store submission on the privacy side.**
Until B4 exists, the honest answer to "can users request data deletion?" is
"only by contacting us", which needs a support email that does not exist yet
(**TODO**).

---

## 6. Draft answers

### Apple — App Privacy

| Category | Collected | Linked to user | Used for tracking |
|---|---|---|---|
| Health & Fitness | Yes | Yes | No |
| Contact Info (name) | Yes | Yes | No |
| User Content (photos) | Yes — processed by Gemini, stored on device only | Yes | No |
| Location (coarse) | Yes — not stored | No | No |
| Identifiers | Yes | Yes | No |
| Diagnostics | Yes | Yes | No |

### Google Play — Data Safety

| Type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Personal info — name | Yes | No | No | App functionality |
| Health and fitness | Yes | No* | No | App functionality |
| Photos | Yes | **Yes** — sent to Google's Gemini API for reading | Yes (only if the user scans) | App functionality |
| Location — approximate | Yes | **Yes** — map/search provider | Yes (only on the nearby screen) | App functionality |
| App activity | Yes | No | No | App functionality |
| Device or other IDs | Yes | No | No | App functionality |

\* "Shared" in Play's sense means transferred to a third party. Supabase and
Firebase are processors acting for us, which Play does not count as sharing —
but **the alert text sent through FCM contains health data**, and the photo
sent to Gemini is health data. **TODO:** have the company's reviewer confirm
how each of those should be declared.

---

## 7. TODO before either form is filed

1. **Gemini data retention.** Whether images sent to the Gemini API are
   retained or used to improve models depends on the API tier and the terms
   in force for the company's account. Confirm in writing, and if retention is
   possible, that must be disclosed. This is the most consequential unknown
   here.
2. **Supabase at-rest guarantees** for the company's plan (§4).
3. **A support / privacy contact email**, required by both stores and by §5.
4. **The privacy policy and terms URLs** themselves (B5). This document is the
   input for writing them, not a substitute.
5. **Account deletion** (B4) — until it exists, the deletion answers above are
   incomplete.
6. **Age rating / children's data.** The app targets elderly patients, but
   there is no age gate and nothing prevents a younger user. Confirm the
   intended rating and whether any children's-data rules apply.
7. **Data residency.** Confirm which region the Supabase project runs in and
   whether Egyptian users' health data crossing borders needs disclosure.
