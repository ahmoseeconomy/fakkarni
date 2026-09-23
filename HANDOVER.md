# Fakkarni — handover

Arabic-first (RTL) medication reminder for elderly patients in Egypt, plus a
read-only admin dashboard. Two Flutter packages in one repo:

| Path | Package | Target |
|---|---|---|
| `.` | `fakkarni` | Android + iOS app (patient and caregiver) |
| `admin/` | `fakkarni_admin` | Flutter Web dashboard, owner-only |

`CLAUDE.md` is the engineering guide — product rules, architecture decisions
and the reasoning behind them. Read it before changing anything; this file is
only what an owner needs to build, ship and operate.

---

## 1. Toolchain

Versions below are read from this machine and this repo, not from memory.

| Tool | Version | Where it is pinned |
|---|---|---|
| Flutter | 3.47.1 (stable, rev `6655482ec0`) | `.metadata`, `.github/workflows/android-lockscreen.yml` |
| Dart | 3.13.1 | ships with Flutter; `environment: sdk: ^3.13.1` in both pubspecs |
| Xcode | 26.5 (17F42) | not pinned — match or exceed |
| CocoaPods | 1.17.0 | not pinned |
| Android Gradle Plugin | 9.1.0 | `android/settings.gradle.kts` |
| Gradle | 9.3.1 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Kotlin | 2.4.0 | `android/settings.gradle.kts` |
| google-services plugin | 4.5.0 | `android/settings.gradle.kts` |
| JDK | 25.0.3 (Android Studio JBR) | not pinned; Java/Kotlin **compile level is 17** |
| compileSdk | 36 | Flutter default (`flutter.compileSdkVersion`) |
| minSdk | 24 | Flutter default (`flutter.minSdkVersion`) |
| targetSdk | 36 | Flutter default (`flutter.targetSdkVersion`) |
| iOS deployment target | 15.0 | `ios/Runner.xcodeproj/project.pbxproj` |

There is deliberately **no `firebase-bom`**: the Flutter Firebase plugins carry
their own versions and a BOM on top conflicts with them.

---

## 2. Build from a clean machine

### 2.1 Once

```bash
git clone <repo> && cd fakkarni
cp secrets.example.json secrets.json     # then fill in the real values
flutter pub get
(cd admin && flutter pub get)
```

**`secrets.json` lives at the repo root and is gitignored.** It is never
committed and never passed to the admin web build (see §6). Every key it holds
is described in `secrets.example.json`.

### 2.2 Android

```bash
flutter build apk --release --dart-define-from-file=secrets.json
# or, for Play:
flutter build appbundle --release --dart-define-from-file=secrets.json
```

Requires `android/app/google-services.json` (present, Firebase project
`fakkarni-5704c`).

> **Release builds are currently signed with the debug keystore**
> (`android/app/build.gradle.kts`, `buildTypes.release`). This is blocker B6 —
> Play will not accept it.

### 2.3 iOS

```bash
(cd ios && pod install)
flutter build ipa --release --dart-define-from-file=secrets.json
```

Signing is not configured in the repo; set the team in Xcode against the
company's Apple Developer account. There is **no `GoogleService-Info.plist`**
and no push entitlement — iOS push is blocker B3.

### 2.4 Admin dashboard

```bash
bash admin/tool/deploy.sh              # build + secret-leak check + deploy
bash admin/tool/deploy.sh --no-deploy  # build + check only
```

The script reads **only** `SUPABASE_URL` and `SUPABASE_ANON_KEY` from
`secrets.json`, runs `admin/tool/leak_check.sh` against the built bundle, and
aborts the deploy on any hit. A web bundle is public, so `GEMINI_API_KEY` must
never reach it — that is what the check exists to prevent.

First deploy only:

```bash
npm i -g firebase-tools && firebase login
firebase hosting:sites:create fakkarni-admin
```

**Two one-off steps before anyone can sign in** (`0021_admin.sql` is already
applied, but it seeds no admin — an allow-list with a name in it would have
been a decision hidden in a migration):

1. Allow-list the email, in the Supabase SQL editor:
   ```sql
   insert into private.admins (email) values (lower('OWNER_EMAIL_HERE'))
   on conflict (email) do nothing;
   ```
2. Create that user: Supabase dashboard → Authentication → Users → Add user,
   same email, **Auto Confirm User** ticked. There is no sign-up or
   password-reset screen in the dashboard, by design.

Both halves are needed: an allow-listed email with no Auth user cannot log in,
and an Auth user who is not allow-listed gets «الحساب ده مش أدمن».

---

## 3. App identifiers

| Item | Value |
|---|---|
| Android `applicationId` | `com.fakkarni.fakkarni` |
| iOS bundle ID | `com.fakkarni.fakkarni` |
| Display name | «فكرني» (`android:label`, `CFBundleDisplayName`) |
| Version / build | `1.0.0+1` (`pubspec.yaml`) |
| URL schemes / URL types | **none** — no `CFBundleURLTypes`, no custom scheme |
| Deep links | **none** — no App Links, no Universal Links, no intent filters for links |
| iOS queried schemes | `tel` (`LSApplicationQueriesSchemes`) — emergency contacts and the ambulance button |
| iOS file sharing | `UIFileSharingEnabled` — PDF exports land in Files |
| In-app products | **none** — no store products, no paywall, no billing SDK |

**Android permissions** (`android/app/src/main/AndroidManifest.xml`):
`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`,
`VIBRATE`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`.
Deliberately **absent**: `USE_EXACT_ALARM` and
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — both are restricted on Play and would
put the listing into review for no gain.

**iOS usage strings**: camera, photo library, location-when-in-use. No contacts
permission — the contact picker runs out of process and needs none.

### Notifications

| Platform | State |
|---|---|
| Android | FCM configured (`google-services.json`), token registration built and unit-tested. **Never verified on hardware** — every escalation so far resolves to `no_token`. |
| iOS | **Not configured.** No APNs key, no `GoogleService-Info.plist`, no push entitlement. Local notifications work; remote push does not. Blocker B3. |

Local notifications (dose reminders, the escalation ladder, appointments) work
on both platforms and are the core of the product. Channels on Android:
`fakkarni_escalation`, `fakkarni_caregiver`, `fakkarni_appointment`,
`fakkarni_checkup`.

---

## 4. Backend inventory

### 4.1 Supabase

Project ref **`uyhelimwadgxhecnfumo`** (`https://uyhelimwadgxhecnfumo.supabase.co`),
already transferred to the company org. Keys are not in this file — see
`secrets.example.json`.

SQL is **run by hand in the SQL editor**, in numeric order. There is no
`supabase db push` in this project. `supabase/README.md` has the paste order;
`supabase/verify_migrations.sql` is a read-only check that answers "which
migrations are actually applied" against the live database.

| # | File | What it does |
|---|---|---|
| 0001 | `schema.sql` | Cloud mirror of the local drift schema; uuid PKs minted on the device |
| 0002 | `rls.sql` | Row-level security — the entire security model |
| 0003 | `invites.sql` | Invite codes + `create_invite`/`redeem_invite`, the one gate through the wall |
| 0004 | `sync.sql` | Server `updated_at` via moddatetime triggers |
| 0005 | `fix_patients_select.sql` | Fixes a recursive `patients_select` that broke every insert |
| 0006 | `push.sql` | `device_tokens`, `escalations`, `private.due_escalations` (the one selection query) |
| 0007 | `escalate_rpc.sql` | Narrow `public` wrapper so the Edge Function can call the private scan |
| 0008 | `escalation_cron.sql` | pg_cron job that ticks the escalation scan |
| 0009 | `escalation_retry.sql` | An interrupted send retries after 5 minutes; atomic claim |
| 0010 | `dose_superseded.sql` | Adds the `superseded` dose state |
| 0011 | `escalate_missed.sql` | Server escalates on `missed` as well as `pending` |
| 0012 | `health_file.sql` | Health file in the cloud: records, readings, lab results, questions, emergency |
| 0013 | `ai_reads.sql` | AI read log and daily cap (from the reverted C2 round; applied, unused) |
| 0014 | `soft_stop.sql` | Soft stop/remove for medications and dose schedules |
| 0015 | `checkup_dates.sql` | Per-stage follow-up dates on `records` |
| 0016 | `lab_ranges.sql` | The lab paper's own printed reference range |
| 0017 | `follow_kind.sql` | Follow-up kind: lab or visit |
| 0018 | `device_health.sql` | Self-check heartbeat per (patient, install) — safety codes only |
| 0019 | `battery_state.sql` | Battery optimisation state, three values |
| 0020 | `caregiver_preferences.sql` | Follower name/relation, alert scope, quiet hours; subscription seam |
| 0021 | `admin.sql` | Admin allow-list + four read-only RPCs for the dashboard |

**All of 0001–0021 are applied and verified on the live project**
(0001–0020 on 22 Sep 2026; `0021_admin.sql` on 23 Sep 2026, after which
`verify_migrations.sql` returned 21 rows, all `ok = true`). Re-run that script
rather than trusting this line — it goes stale the moment anyone touches the
project, and it is one paste.

### 4.2 pg_cron jobs

| Job | Schedule | What it does |
|---|---|---|
| `fakkarni-escalate` | `*/5 * * * *` | Calls the `escalate` Edge Function to alert caregivers about doses still unconfirmed past the server grace window (60 min) |
| `fakkarni-purge-records` | `17 3 * * *` | Backstop that clears cloud rows for records the patient deleted |

Both read their secrets from Vault at run time, never from the stored command.
When an alert does not arrive, look in `cron.job_run_details` and
`net._http_response` first.

### 4.3 Edge Functions

| Function | State | What it does |
|---|---|---|
| `escalate` | **deployed and running** | Claims a due escalation row, sends the FCM push to the caregiver, records the delivery status. Service-role bearer required. |
| `ai-read` | **in the repo, not in use** | Server-side Gemini proxy with per-user daily caps. Built in round C2, then reverted for latency; kept so the revert can be reverted. |

### 4.4 Storage buckets

**None.** No Supabase Storage bucket exists and nothing uploads an image.
Prescription and lab photos are written to the device's own documents
directory and referenced by `records.attachment_path`, which is **local-only
and never synced** (enforced by `test/data/sync/health_file_sync_guard_test.dart`).
Deleting a record deletes its file immediately. Retention of photos is
therefore "until the patient deletes the record or the app".

### 4.5 Firebase

Project **`fakkarni-5704c`**.

| Service | Use |
|---|---|
| Cloud Messaging | Caregiver escalation push. Android configured; iOS not (B3). |
| Hosting | The `admin/` dashboard, site `fakkarni-admin`, target `admin` in `firebase.json`. |

No Analytics, no Crashlytics, no Firebase Auth (authentication is Supabase).

### 4.6 Gemini

| Item | Value |
|---|---|
| Model | `gemini-3.6-flash` (`lib/ai/gemini_config.dart`) |
| Fallback | `gemini-flash-latest`, one shot, on 404/503/429/timeout |
| Endpoint | `generativelanguage.googleapis.com`, called directly from the app |
| Called from | `lib/ai/prescription_reader.dart` — prescriptions, lab reports, medicine boxes |
| Key | `GEMINI_API_KEY`, `--dart-define` only, **compiled into the binary** (B2) |

Images are shrunk once in the transport (`lib/core/images/shrink_for_ai.dart`)
before being sent, because Gemini bills by image dimensions.

---

## 5. Not built yet / blockers for public release

Nothing below is an oversight; each is a decision or a dependency on an account
the company now owns. **Every one of B1–B6 blocks a store submission.**

| ID | Blocker | Detail |
|---|---|---|
| **B1** | **Real sign-in replacing anonymous auth** | The only working sign-in is `signInAnonymously`. An anonymous user is bound to one device and is lost when app data is cleared — a caregiver link dies with it. Google sign-in is written as a dormant sibling (`lib/data/auth/google_auth_service.dart`) and needs client IDs; Apple sign-in is mandatory once Google is offered (Guideline 4.8) and needs the paid Apple account. **Shipping with anonymous auth is forbidden.** |
| **B2** | **Gemini API key ships inside the binary** | Extractable from any APK/IPA in minutes. The quota is spent by strangers and you find out from the bill. The fix already exists in the repo: re-apply the reverted C2 round (`supabase/functions/ai-read/`, `0013_ai_reads.sql`), which moves the key to an Edge Function secret. |
| **B3** | **iOS push (APNs) not configured** | No APNs key, no `GoogleService-Info.plist`, no push entitlement. The caregiver escalation — the product's whole differentiator — cannot reach an iPhone. Also request the **Critical Alerts** entitlement from Apple, which is the only remaining way to make that alert bypass silent mode. |
| **B4** | **No in-app account deletion** | Apple (5.1.1(v)) and Google both require an in-app path to delete the account and its data for any app that creates accounts. Sign-out exists; deletion does not. Needs a screen plus a server-side delete for `patients` and everything cascading from it. |
| **B5** | **No privacy policy or terms URLs** | Both stores require a reachable privacy policy URL, and this app handles health data. Nothing in the app links to one and no URL exists. `docs/STORE_LISTING_DATA.md` is the input for writing it. |
| **B6** | **No Play upload keystore** | Release builds are signed with the debug keystore. Generate an upload key, store it outside the repo, and wire `key.properties` into `android/app/build.gradle.kts`. Enrol in Play App Signing. |
| B7 | Payments are not built | The pricing model is decided (patient pays for his account; every follower pays for his own) but there is no billing code, no products and no paywall. The server-side seam exists and returns `true` for everyone: `private.follower_subscription_active`. Two safety questions must be answered before it ships — see «Pricing» in `CLAUDE.md`. |
| B8 | Android escalation never verified on a real device | The CI emulator test proves a notification-button tap reaches Dart and writes the dose row. It does **not** prove manufacturer battery killers, real Doze, or that the cloud was told. No physical Android device has been through the chain. |
| B9 | Public OpenStreetMap services | «قريب منك» uses the public Overpass and tile servers, whose policies do not cover an app at scale. Needs our own instance or a paid provider before launch. |
| B10 | Every install creates an empty patient row | A caregiver's phone holds a patient row that is not a patient. Harmless today (it never reaches the cloud) but it is the wrong shape and a refactor of everything reading `patientId`. |

---

## 6. Key rotation checklist

Rotate everything below after handover — the previous developer has seen all of
it. Order matters where noted.

| Key | Where it is used | Rotate by | If rotated after release |
|---|---|---|---|
| **Supabase service-role key** | `escalate` Edge Function (bearer), pg_cron via Vault | Supabase dashboard → API keys, then update the Vault secret **and** redeploy the function | Escalation stops silently until both are updated. No client impact. |
| **Supabase anon/publishable key** | Mobile binary, admin web bundle | Supabase dashboard | **Every installed app breaks** until users update. Rotate before first release, not after. |
| **Gemini API key** | Mobile binary (B2) | Google AI Studio | **Scanning breaks in every installed app** — the key is baked in. This is exactly why B2 must be paid before launch. |
| **Firebase service account** (used by `escalate` to sign FCM requests) | `escalate` Edge Function secret | Firebase console → service accounts, then update the function secret | Caregiver push stops. No client impact. |
| **FCM / `google-services.json`** | `android/app/google-services.json` | Firebase console | Only changes if the Firebase project changes; then all existing installs lose push until updated. |
| **Play upload key** (B6, does not exist yet) | Android release signing | Create once, store outside the repo | Cannot be rotated freely after release unless enrolled in Play App Signing — enrol from the start. |
| **Apple signing / APNs key** (B3, does not exist yet) | iOS push | Apple Developer account | APNs keys can be revoked and reissued; update the Firebase iOS config. |
| **Admin dashboard passwords** | Supabase Auth users allow-listed in `private.admins` | Supabase dashboard | Only affects dashboard access. |

**Not a secret, no rotation needed:** the Supabase project URL and the Firebase
project ID. Both ship in every binary by design; RLS and `private.is_admin()`
are the wall, not obscurity.

---

## 7. Accounts to transfer

| Account | Status |
|---|---|
| GitHub repository | to transfer |
| Supabase | **already in the company org** |
| Firebase / Google Cloud (`fakkarni-5704c`) | to transfer |
| Google AI Studio (Gemini key owner) | to transfer, then rotate |
| Apple Developer | to create/transfer — blocks B3 and Apple sign-in |
| Google Play Console | to create/transfer — blocks B6 |

---

## 8. Tests and checks

```bash
flutter test                 # mobile — 1399 tests
(cd admin && flutter test)   # admin  — 50 tests
flutter analyze && (cd admin && flutter analyze)
dart run tool/generate_licenses.dart   # regenerates THIRD_PARTY_LICENSES.md
```

CI (`.github/workflows/android-lockscreen.yml`) runs **only** the Android
emulator lock-screen test. It does not run `flutter test` or `flutter analyze`
for either package — those are manual today, and wiring them into CI is the
cheapest first improvement after handover.
