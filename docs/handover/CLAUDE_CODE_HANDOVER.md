# Fakkarni — Claude Code handover

Last updated: 2026-09-28 (late night). Place this file at `docs/handover/CLAUDE_CODE_HANDOVER.md` and read it before any task.
The owner (Mohamed Saad) writes prompts in English; UI copy is Egyptian Arabic.

## 1. Project

- **App:** «فكرني». It replaces the company's old app «فكّرني» (`com.fakrny.app`). The old app has no real users, so no data migration.
- **Stack:** Flutter · drift (local DB) · Supabase (Postgres + RLS + Edge Functions + pg_net + Vault + pg_cron) · FCM · Gemini (free key; never send real patient data) · ElevenLabs «ممدوح» voice mp3s in `assets/voices`.
- **Repo:** `github.com/ahmoseeconomy/fakkarni`, branch `main`.
- **Supabase project ref:** `uyhelimwadgxhecnfumo` (Frankfurt, NANO).
- **Bundle IDs:**

  | Platform | ID |
  |---|---|
  | iOS | `com.fakrny.app` (team DEMANDCOM) |
  | Android | `com.fakkarni.fakkarni` |

- **Version:** `2.0.0+2`. It is on TestFlight 2.0.0(2) and on Play internal testing. The next build is `2.0.0+3`.

## 2. Recent commits (newest last)

| Commit | Change |
|---|---|
| `e0cc974` | Single `MedicationSaveService`, plus reconcile on start and resume. Every add/edit path goes through it. |
| `9754013` | Boss requests: nearby call/WhatsApp/directions/specialties; booking only with real doctors; «كلّمني» answers from the patient's data. |
| `5330baf` | On-device voice NLU (`lib/domain/voice/nlu/`) with a written confirm step («صح كده / عيد كلامك»). |
| `52466ab`, `915bb29` | No guessed times anywhere; manual entry starts with empty «اختار الساعة» rows. |
| `458231e` | `MedName` / `NameTimeRow` (`lib/core/widgets/med_name.dart`): name on the right, time on the left. Latin names use a proper font (`no_monospace_test`). «ملفّي» header. |
| `13ad11d` | «صيدليتي»: from nearby, from a photo of the pharmacy card (Gemini), or typed manually. |
| `b4693b4` | Nurse account upgraded to a full copy of the patient app (2696 tests). Nurse edits become `medication_changes` rows that apply automatically on the patient phone, with «تراجع» for 24h. |
| `8c20bf5`, `2aba006`, `8a22df2` | Fixes to migration 0035: 24h confirm-signal window, self-check moved to the end of the file, required-columns fixtures + `selfcheck_required_columns_test`. |

## 3. Server state (verified 2026-09-28)

### Migrations

| Migration | Status | Contents |
|---|---|---|
| **0034** `meal_relation` | Applied | `dose_schedules.meal_relation` (routine removal). |
| **0035** `nurse_full_edit` | Applied | 6 new `medication_changes` kinds; `reverted` + `reverted_at`; pharmacy columns on `patients`; nurse prefs; escalation rung `nurse` (+30 min); `claim_escalation_for_service`; confirm-signal triggers (last 24h only). |
| **0036** | Reserved | PRN («عند اللزوم»), branch `wip/prn-round3`. **Do not reuse this number.** |

### Edge Functions deployed

- `escalate` (updated).
- `confirm-signal` (new).
- Also in the repo: `ai-read`, `delete-account`, `verify-purchase`.

### Vault

- `confirm_signal_function_url` exists.
- `escalate_service_role_key` exists.

### Postgres errors

- The 1,218 errors in the last 24h came before 0034/0035 was applied.
- The last hour had zero errors.

### Escalation ladder

| Step | Who | Where it runs |
|---|---|---|
| +15 / +30 min | Patient | On the phone |
| +30 min | Nurse | Server |
| +60 min | Son | Server |

When a dose is confirmed on either side, a silent FCM data push silences the other side. iOS still needs the APNs `.p8` from the company.

## 4. Hard rules

### Security

- Never read or print secrets (`secrets.json`, `key.properties`, `.jks`, tokens).
- `service_role` and Firebase service accounts never go in the app or the repo.
- Never commit any of these:
  - `ios/Runner.xcodeproj/project.pbxproj`
  - `secrets.json`
  - `key.properties`
  - any `.jks`
- Never take keys from the old app. New restricted keys go in `secrets.json`.

### Supabase

- You write migrations; the owner reviews and applies them by hand. Never apply to live.
- Never create users or data on live Supabase.
- Never `GRANT` to `anon`, and never loosen RLS.
- Every migration has a self-check at the **end** of the file, and its fixtures must fill all NOT NULL columns.

### Commits and tests

- Never commit while any test fails.
- Make one change at a time.
- Run `flutter analyze`, the full suite, and the contrast audit (`test/support/contrast_audit.dart`, light and dark).

### Reminders

- Every add/edit path goes through `MedicationSaveService`.
- Non-dose features must never touch reminders.
- No `fullScreenIntent`, no `USE_EXACT_ALARM`, and no critical alerts.
- Respect the iOS 64-notification budget.
- Medicine reminders never stop because of billing.

### Patient-facing UX

- No technical text, error codes, or monospace — ever.
- Never invent times, doctors, or data such as «متوفر» or «يقبل تأمينك».

### Colors and layout

- Colors come from `theme/tokens.dart` only; no new hex values.
- Red is for emergencies only (`red_only_in_emergency_test`).
- Gold means "needs attention now".
- At most two primary buttons per screen. The exception is nearby cards, where the call button is filled on every card.

### Voice

- «ممدوح» recordings only; no `flutter_tts` for automatic patient speech.
- Keep `voice_placement_test` green.

### Devices

- Never use `flutter install`.
- Lock-screen tests run only in profile or release builds.

## 5. Next prompt (not sent yet): automatic self-diagnosis

Goal: the user never checks anything by hand.

1. **Checks on the phone.** Runs on start, on resume, after any schedule change, and once a day in the background. It checks:
   - notification permission;
   - exact alarms and battery optimization (Android);
   - pending vs expected reminders;
   - session;
   - last sync;
   - FCM token;
   - timezone.
2. **Heals silently.** It runs reconcile and refreshes the session/token.
3. **Reports** codes only (no health data) to `device_health`. This also fixes its RLS 42501.
4. **New migration** at the next free number after 0036, containing:
   - RLS on `device_health`;
   - an hourly pg_cron job that marks a device `silent` after 48h with no report;
   - an owner-only view `admin_device_health`.
5. **Hides** «للمطوّر» (diagnostic log and «اطمن إن التذكير هيشتغل») in release builds.

The full prompt text is in the owner's Arabic handover, section ٨ (د).

## 6. Open items

- **Simulator test:**
  - a nurse edit rings on the patient phone and shows «تراجع»;
  - a confirmation on either side silences the other;
  - the nurse gets the +30 alert;
  - the son view is unchanged.
- **Lock-screen «أخدته» on the first notification:** unverified. The test matrix is in `docs/testing/lock_screen_action.md`.
- **Nurse:** «كلّمني» and adding by voice are still missing.
- **Tests:** extend `selfcheck_required_columns_test` to 0035 and later migrations.
- **Places API key:** new and restricted, in `secrets.json`.
- **Waiting on the company:** APNs `.p8`.
- **Before any store release:**
  - real sign-in (email, Apple, Google);
  - privacy policy (`docs/legal/`);
  - subscription products;
  - redeploy `delete-account`;
  - `ITSAppUsesNonExemptEncryption=false`.
- **«صيدليتي»:** the call number is stored in shared_preferences (`pharmacy.call`). It should move to the synced record now that 0035 added the `patients.pharmacy_*` columns.

## 7. Devices

| Device | ID |
|---|---|
| iPhone "saad" | `00008120-000A1CC8267BC01E` |
| Simulator: patient (iPhone 17 Pro) | `0FC0B7ED-0E9C-4810-AF77-79948B8394B5` |
| Simulator: nurse (iPhone 17) | `6C655936-9DE4-4D50-B386-A22392494505` |
| Simulator: son (iPhone Air) | `FEA520B3-A3BD-4967-9D15-DB35FA6D2D6F` |

To run on the iPhone:

```
flutter run --profile -d 00008120-000A1CC8267BC01E --dart-define-from-file=secrets.json
```
