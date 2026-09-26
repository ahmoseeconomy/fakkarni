# Fakkarni — Privacy Policy

> **DRAFT — needs legal review before publication.** Written from what the
> app's code actually does as of 25 September 2026 (build 1.0.0+2), not from
> intent. Placeholders in `[BRACKETS]` must be filled by the company. Where a
> fact depends on a contract or an account setting we could not see from the
> code, it is marked **[CONFIRM: …]** rather than guessed.

**Controller:** [COMPANY_NAME], [COMPANY_ADDRESS]
**Contact for privacy questions and requests:** [COMPANY_EMAIL]
**Last updated:** [DATE]

## 1. What Fakkarni is

Fakkarni («فكّرني») is a medication-reminder app for older adults. A patient
records their medicines and daily routine; the phone reminds them at each dose.
Optionally, the patient can link family members («متابع», follower) and a
nurse or companion («ممرض / مرافق») who can see their medicines and doses, and
who are alerted if a dose is not confirmed.

## 2. The short version

- **Without linking anyone, your data stays on your phone.** The app works
  fully offline. Nothing is uploaded until you link a family member or nurse.
- **When you link someone, a copy of your health data is kept on our cloud
  database** so the people you chose can see it and be alerted.
- **We do not sell data, show ads, use analytics or tracking SDKs, or build
  profiles.**
- **You can delete your account and all of its data from inside the app**
  (Settings → «امسح حسابي»). See §8.

## 3. What we collect, and why

### 3.1 On your phone only (never uploaded by us)

| Data | Why |
|---|---|
| Emergency contacts (names, phone numbers, relation) | The emergency card on your phone. There is no place for them in our cloud. |
| Sex and age (optional) | Choosing the right Arabic wording («بتفطر» / «بتفطري»). |
| Photos of prescriptions, lab reports and imaging — **unless** you turn on «شارك صور الورق مع الممرض» (§3.2) | Kept as the paper of the record you saved. |
| Your pharmacy's name and WhatsApp number | Opening a WhatsApp message to it when you choose to. |
| Water counter, night-mode setting, notification settings | Display and reminders on this phone. |

### 3.2 On our cloud, only after you link a family member or nurse

| Data | Why |
|---|---|
| Your first name (as you typed it) | Shown to the people you linked. |
| Medicines: name, amount, purpose and instructions you entered, alert mode, start/stop, "not bought yet", stock count if you track it | So your circle sees what you take and can help. |
| Dose schedules (meal-based times or clock times, day patterns) and dose events (scheduled time; taken, missed or skipped) | So your circle sees today's doses, and so our server can alert them if a dose is not confirmed. |
| Your daily routine times (wake, meals, sleep) | Stored with the schedule. |
| Health file: prescriptions, lab results (with the range printed on the paper), visits, imaging, appointments and follow-ups, blood-glucose readings, other measurements (blood pressure, pulse, weight, oxygen, temperature), questions for the doctor | So your circle can see your health file. |
| Emergency profile: blood type, allergies, chronic conditions (no phone numbers) | Shown on your circle's emergency card. |
| Medicine photos you took | Shown next to the medicine name to your circle. |
| Photos of your papers — **only if you turn on** «شارك صور الورق مع الممرض» | Shown to your nurse (not to followers). Turning it off deletes them from our cloud. |

### 3.3 About the people in the circle

| Data | Why |
|---|---|
| A pseudonymous account ID (we do not ask for email or phone number to create an account) | Linking and access control. |
| Display name and relation («ابن» / «بنت» / other) that the follower or nurse enters, quiet hours and alert preferences | Telling the patient who follows them, and when to send non-urgent notices. |
| Role and permissions (follower / nurse; may confirm doses; may edit medicines) | Access control. |
| Confirmations made by a nurse on the patient's behalf, and medicine-change requests they sent, with their display name | Applied on the patient's phone and shown to the patient. |
| Push-notification token | Delivering alerts to their phone. |
| Missed-dose alert records (which dose, when, delivery status) | Showing the alert and preventing duplicates. |

### 3.4 Technical data

| Data | Why |
|---|---|
| Device health codes: app version, platform, OS version, time zone, notification permission, battery-optimisation state, number of pending reminders, reminder coverage, last sync time, an install ID | Detecting phones where reminders have silently stopped, so we can fix them. **No medical content.** |
| Subscription state: store, product, trial/active/expired, expiry, who bought it | The family subscription (§6). Payment details stay with Apple/Google; we never see card data. |
| Server logs kept by our hosting provider (e.g. IP address and request time) | Security and operations. [CONFIRM: log retention for the Supabase plan] |

We do **not** collect: your contacts list (the contact picker returns only the
one contact you pick, and we store it on your phone only), advertising ID,
browsing history, or precise location (see §5).

**Voice («اتكلم»):** with the voice companion on, you can answer short
questions by voice (yes/no, a time, a number). The microphone is on **only
while you press the «اتكلم» button** and stops by itself after a short
silence. **We never record, store or upload your voice**, nor the transcript —
it is interpreted on the phone and discarded. Speech is converted to text by
your phone's own speech-recognition service (Apple or Google); we ask it to run
**on the device** without internet, and where the phone cannot do that for
Arabic, the system sends the audio to Apple's or Google's servers under their
terms (see §5). You can turn voice off in Settings or decline the microphone
permission; everything keeps working by touch.

## 4. How long we keep it

| Data | Kept |
|---|---|
| Everything on your phone | Until you delete it, delete your account, or uninstall the app. |
| Cloud data of a linked account | While the account exists. Deleted immediately when you delete your account (§8). |
| A record you delete | Removed from the cloud on the next sync; a daily job removes any left behind within 30 days. |
| «فلان خرج من الدايرة» notices | 30 days. |
| Anonymous count of deleted accounts (date and type only) | Kept, with no personal data. |
| Backups kept by our hosting provider | [CONFIRM: backup retention period for the Supabase plan] — deleted data disappears from backups when they expire. |

## 5. Who receives your data (processors and third parties)

| Who | What | When |
|---|---|---|
| **Supabase** (database, accounts, file storage) — region [SUPABASE_REGION] | Everything in §3.2–3.4 | After you link someone. |
| **Google — Gemini API** | The **photo** you choose to scan (prescription, lab report or medicine box) and our instructions to read it | Each time you scan. **In this version the photo is sent from your phone directly to Google, not through our server.** The result is shown to you and saved only after you confirm. [CONFIRM: Gemini API data-use and retention terms for the company's account] |
| **Google — Firebase Cloud Messaging** (Android), and **Apple Push Notification service** once enabled | The alert sent to a follower or nurse, **which includes the patient's name and the medicine name** | When a dose is not confirmed in time. |
| **Apple** (App Store) / **Google** (Play) | Purchase receipts, verified by our server | When someone buys or restores the family subscription. |
| **Map search**: Apple Maps on iPhone; OpenStreetMap (Overpass and map tiles) on Android | Your **approximate** location, rounded to about 110 m before it leaves the phone | Only when you open «القريب مني» and search. |
| **WhatsApp**, maps apps, the phone dialer | Only what you choose to send or call | Only when you tap the button. |
| **System speech recognition** (Apple on iPhone, Google on Android) | **Your voice** while you answer with the «اتكلم» button — to turn it into text | Only when you press «اتكلم». We request **on-device** recognition; where the phone cannot do that for Arabic, the system sends the audio to Apple/Google servers. We never receive or store the audio. [CONFIRM: which devices and OS versions recognise Arabic on-device — the company measures this on real phones] |
| **Our operators** ([COMPANY_NAME]) | An admin dashboard showing account names, follower names and device health — **no medicines, doses, health file, measurements or phone numbers** | For keeping reminders working. |

We do not sell or rent personal data, and we do not share it for advertising.

## 6. Family subscription

One subscription per patient covers the patient and up to five followers or
nurses; anyone in the circle may pay. **Reminders on the patient's phone never
stop because of payment.** Subscriptions are billed and cancelled only through
Apple or Google. Deleting your account does not cancel a store subscription —
cancel it in your Apple or Google account settings.

## 7. Security

All connections use HTTPS. Access to cloud data is enforced by row-level
security in the database: a person can read a patient's data only if the
patient linked them. Only the patient's own phone writes their health data — a
nurse's confirmations and change requests are stored as requests and applied by
the patient's phone.
Data on the phone relies on the phone's built-in encryption.
[CONFIRM: at-rest encryption guarantees of the Supabase plan]

## 8. Your choices and rights

- **Delete your account:** Settings → «امسح حسابي» → confirm twice. For a
  patient this deletes the account and all cloud data (medicines, doses,
  health file, measurements, photos, emergency profile, links) and wipes the
  app on this phone. For a follower or nurse it deletes their account, links,
  name and preferences; the patient's own data is not deleted (it belongs to
  the patient), confirmations they made stay without their name, and the
  patient sees that they left the circle. If you cannot use the app, email
  [COMPANY_EMAIL] or use [ACCOUNT_DELETION_URL].
- **Unlink** someone at any time (Settings → «عيلتك أو ممرضك»).
- **Stop sharing paper photos** with your nurse at any time.
- **Access or correct** your data: most of it is visible and editable in the
  app; for anything else write to [COMPANY_EMAIL].
- [CONFIRM: rights under applicable law, e.g. Egypt Personal Data Protection
  Law No. 151 of 2020, GDPR if applicable, and the supervisory authority]

## 9. Children

Fakkarni is not directed at children under [16]. We do not knowingly collect
data from children. If you believe a child has provided data, contact
[COMPANY_EMAIL] and we will delete it.

## 10. Health information

Fakkarni does not give medical advice and does not diagnose. It reminds you of
what you and your doctor decided. Readings from photos are suggestions that you
must confirm. Always ask your doctor or pharmacist.

## 11. Changes

We will update this policy when the app changes what it collects, and show the
date above. [CONFIRM: how users are notified of material changes]
