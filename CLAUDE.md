# Fakkarni (فكرني) — Project Guide

Arabic-first (RTL) medication reminder app for elderly patients in Egypt.
Its differentiator: when a **critical** dose is missed, the app runs an
**escalation ladder** that ends at the caregiver (the patient's adult child) —
the patient is never left alone with a notification he already missed.

Two users, different needs:
- **The patient** — ~72 years old, reading glasses, uses the app under pressure.
- **The caregiver** — working adult, checks briefly, pays for the subscription.

---

## Non-negotiable rules

These are product decisions, already settled. Do not "improve" them without asking.

1. **A dose is an anchor + an offset by default. A fixed clock time is the
   documented exception, never the first thing offered.**
   Timing is the sealed `DoseTiming`: `AnchorTiming(anchor, offsetMinutes)`
   — `{anchor: breakfast, offsetMinutes: -30}` — is the default and the
   primary control everywhere. `FixedTiming(minuteOfDay)` exists for the
   prescription that genuinely says "8:00 sharp"; it is reached only through
   the small link *under* «احفظ الجرعة» (a clock is familiar and anchors are
   new — a link beside the chips would get tapped out of habit, not fit), and
   the editor must say plainly «ساعة ثابتة — مش هتتحرك مع روتين يومك».
   The rule was not abandoned: anchors are still why Ramadan, travel and late
   wake-ups work by editing one field. Fixed doses simply stay where the
   patient put them when the routine changes. Never make fixed the default,
   never persist a resolved time for an anchor dose, and keep the fixed minute
   in `fixed_timings` — not as a column on every schedule.

2. **`lib/domain/` stays pure Dart.** No Flutter, no database, no IO, no
   plugins. Pure functions are why the engine is unit-tested in under a second.
   If a feature needs a dependency, it does not belong in `domain/`.

3. **Never auto-stop a medication.** `durationDays == null` means open-ended and
   the reminder runs forever until a human stops it. Never infer a duration.

4. **AI proposes, a human confirms.** No OCR/Gemini output ever becomes a
   scheduled dose without an explicit tap on a confirmation screen. On that
   screen, "أعدّل" carries the same visual weight as "تمام" — never nudge
   someone into confirming a medication schedule they have not read.
   Unknowns split into **blocking** and **non-blocking**: an unclear *name
   or timing* blocks «تمام» (nothing to schedule); an unknown *amount* does
   not — it stays gold with its note, «تمام» proceeds with a quiet
   «هتتحفظ من غير الجرعة — تقدر تضيفها بعدين», and the row is saved with
   `amountLabel = null, amountUnknown = true`, which «يومك» surfaces as
   «اسأل الصيدلي عن جرعة …». Never invent a value to unblock a button; never
   forget an unknown silently either. A «١×٣» line with no meal named is
   always flagged, whatever confidence the model reports, because spreading
   it over three meals is our convention, not the paper's.
   «صوّر تاني» is always offered — a bad read is fixed by a better photo,
   not by editing five fields by hand.

5. **A confirmation cancels escalation immediately, at any stage** — including
   after the caregiver has already been alerted. A few seconds of lag here
   means needlessly worrying the son, which is worse than a late alert.

6. **No medical advice, ever.** Default offsets (30 min before food, 15 min
   before bed — one function, `defaultOffsetBefore(anchor)` in `domain/`,
   used by both the editor and the Gemini reader) are editable operational
   conventions, not clinical guidance. If a
   prescription line is unclear the answer is "مش متأكد — اسأل الصيدلي",
   never a confident guess. The app never suggests, changes or stops a drug.

---

## UI rules

- **Body text ≥ 20px. Never below 17px anywhere.** Tap targets ≥ 56px, primary
  buttons 64px. Maximum two primary actions per screen. No icon-only buttons —
  every control carries a word.
- The mockups render small and their type and targets read below these minimums.
  **Take every size from `class F`, never from measuring the image.** Where a
  mockup is tighter than the minimums, the minimums win — and say so.
- **Red belongs to the emergency card and to nothing else.** The mockups spend
  red on the `طوارئ` shortcut in the top bar. That is its only job in this app:
  never use red for an error, a warning, a validation message, or a missed
  dose. A missed dose uses gold and neutral wording — he forgot, he did not
  fail.
- **Gold (`F.gold`) means one thing: "this needs your attention now."** A
  dose that needs taking now, the state you are currently on, and a field the
  AI is unsure about («محتاج تحديد») — all three are that one meaning. Do not
  add a fourth use that isn't; a list of exceptions grows until the colour
  means nothing, a principle does not. The mockups show a coral FAB in the
  bottom bar — build that FAB in green, not coral. Gold must be the only
  colour that pops.
- **No time picker as the primary control.** The dose editor leads with anchor
  chips (`[قبل الفطار] [بعد العشا] …`) plus an offset stepper. A fixed clock
  time exists only as a small secondary link.
- **Copy is warm Egyptian colloquial**, the way a family speaks:
  "بتفطر الساعة كام؟" — not "يرجى تحديد موعد وجبة الإفطار".
- **Any monospace font needs an Arabic fallback in the stack.** IBM Plex Mono
  has no Arabic glyphs; without a fallback Arabic letters render disconnected.

---

## Architecture

```
lib/
  domain/scheduling/          PURE DART — no Flutter imports
    day_routine.dart          DayAnchor, MinuteOfDay, DayRoutine
    dose_schedule.dart        DoseSchedule, DoseRepeat, DoseTiming
                              (AnchorTiming | FixedTiming)
    schedule_engine.dart      resolveTime / resolveFixed / remindersForDay
  ai/                         Phase 2 — gemini_config (key from --dart-define),
                              prescription_reading (pure model + responseSchema),
                              prescription_reader (Gemini REST, http.Client injectable)
  core/theme/tokens.dart      brand colours + elderly-first sizing (class F)
  core/notifications/         NotificationService — local scheduling; tap → lastPayload
  data/db/                    drift (SQLite) v5: patients, day_routines, medications
                              (amount_unknown), dose_schedules (timing_kind),
                              fixed_timings, dose_events — every table carries a
                              device-minted `uuid` (SyncIdentity mixin)
  data/repositories/          routine / medication / dose_event
  data/services/              reminder_plan (pure: IDs, window, payload)
                              reminder_scheduler (engine → sink), reminder_sink
                              notification_actions (lock-screen «أخدته»/«فكّرني بعدين»)
  app/                        AppScope (services), AppRoot (onboarding | today,
                              opens ReminderScreen on tap), bootstrap.dart
                              (buildServices + background action entry point)
  features/onboarding/        5 routine questions
  features/medication/        add medication (anchor chips + offset stepper);
                              EditMedicationScreen — set the amount, stop (two-step)
  features/today/             «يومك» — next dose card + day rail
  features/routine/           EditRoutineScreen — change any anchor after onboarding
  features/link/              SignInScreen — the one door to identity («اربط ابني»)
  data/auth/                  AuthService interface + GoogleAuthService +
                              supabase_init (the only supabase/google imports)
  features/scan/              ScanPrescriptionScreen (advice → «صوّر الروشتة» /
                              «اختار من الصور», one image_picker path for both)
                              + ReviewPrescriptionScreen «فهمت الروشتة كده»
  features/reminder/          ReminderScreen — أخدته / فكّرني بعد ربع ساعة / مش هاخده
test/                         245 passing
```

**The day starts at wake, not midnight.** `minutesFromDayStart` is
`(anchor - wake + 1440) % 1440`, so a 1 AM bedtime lands 18 hours *after*
waking rather than 6 hours before it. A fixed time follows the same rule:
`resolveFixed` puts a 1 AM fixed dose at the *end* of the routine day (next
calendar date), and otherwise never moves it. Both kinds resolve to the same
minute-keyed map, so a fixed 2:00 PM and «قبل الغدا − ٣٠» at 2:00 PM merge
into one `Reminder` like any other pair.

**The Gemini key comes from `--dart-define` only.** `GeminiConfig` reads
`String.fromEnvironment('GEMINI_API_KEY')`; `tryFromEnvironment()` returns
null when missing and the scan screen says so in words, `fromEnvironment()`
throws, and `GeminiPrescriptionReader`'s constructor throws on an empty key —
so no request can ever leave with an empty key. `secrets.json` and `*.env`
are gitignored for `--dart-define-from-file`. Run with
`flutter run --dart-define=GEMINI_API_KEY=…`. Gemini is called over REST
(`responseSchema` JSON) — the `google_generative_ai` package is deprecated,
and a REST call is testable with `MockClient`.

**The model name is Google's to retire, not ours to assume.**
`GeminiConfig.defaultModel` is the single place it lives (currently
`gemini-3.6-flash`; `gemini-2.5-flash` was closed to new users on
2026-09-01 with the only notice being the 404 body: "no longer available to
new users… use models/gemini-3.6-flash"). Override without a code change via
`--dart-define=GEMINI_MODEL=…`. When a scan fails, the logged
`Gemini: HTTP <status>: <body>` line is the source of truth — read it before
touching the request shape; our memory of which model exists is not.

**Pinned, with a loud fallback.** A medication reader must not change its
extraction behaviour silently, so the model stays pinned. But a 404 mid-demo
is worse than a behaviour shift: on `404` + `NOT_FOUND` the reader retries
**once** against `GeminiConfig.defaultFallbackModel` (`gemini-flash-latest`,
override `--dart-define=GEMINI_FALLBACK_MODEL=…`), logs
`Gemini: WARNING pinned model … retired`, and tags the reading with
`modelWarning`, which the review screen shows in debug builds. That warning
is the signal to re-pin deliberately. A `400` never triggers the fallback —
masking a schema rejection is exactly the silent shift being guarded against.

**Image quality beats prompt tuning.** Handwriting dies first under
downscaling. `pickWithSystemCamera` uses `maxWidth/maxHeight 2560,
imageQuality 92`; settle those numbers on a real handwritten prescription,
not on a screen. The system camera is used deliberately (familiar to a
72-year-old, handles focus/exposure/retake); build a custom viewfinder only
if real testing shows framing is what breaks the read.

**The uuid is identity for sync; the int id is plumbing for SQLite.**
Every synced-someday table mixes in `SyncIdentity`: `uuid TEXT NOT NULL
UNIQUE`, minted on the device by a `clientDefault` — never by a server, and
never by a call site (anything a call site must remember will be
forgotten). Auto-increment ids are per-device sequences — two phones both
mint 1, 2, 3 — so the uuid is what sync matches on, while all foreign keys
stay on the local int id. Never expose an int id outside the device.
Schema versions now live under `drift_schemas/` (`drift_dev schema dump`
before and after every schema change) and migrations are proven by
`SchemaVerifier` in `test/data/uuid_migration_test.dart` — written red
before the migration existed, because migrations run on a phone holding
real data.

**Schema changes migrate in place — never wipe.** This database holds real
patients' schedules. `onUpgrade` turns foreign keys off outside the
transaction (the PRAGMA is a no-op inside one), runs every step inside one
transaction, and turns them back on; `beforeOpen` re-asserts them.
`test/data/migration_test.dart` opens a hand-written v2 database with anchor
rows and asserts every schedule and event survived — add a case there for
every future version. **Old migration steps use frozen historical SQL, never
today's drift table definitions**: a step that references the current
definition silently changes shape every time the schema grows (the v2→v3
step broke exactly this way when v5 added `uuid`). Each step must produce
its own version's schema, byte for byte, forever.

**Times are built with `DateTime(y, m, d, 0, totalMinutes)`, never
`.add(Duration)`.** Egypt observes daylight saving; the constructor works in
wall-clock terms and the addition does not.

**Notification IDs are derived, and every feature owns a reserved band.**

An ID is computed from the reminder's slot alone — never allocated, never
stored:

```dart
// lib/data/services/reminder_plan.dart
slot = (epochDay % 32) * 1440 + hour * 60 + minute   // 0 … 46,079
id   = <band base> + patientIndex * 46_080 + slot
```

Same patient, same slot → same ID, forever. Rescheduling therefore re-emits
the identical set of IDs, so a duplicate is impossible by construction rather
than prevented by bookkeeping. The engine already merges same-minute doses
into one `Reminder`, which is what makes a slot unique per patient.

**The patient dimension is not optional.** Two people in one household both
taking something at 8:00 AM would otherwise land on the same ID, and one
reminder would silently overwrite the other. `patientIndex` is a small stable
slot (`patients.notification_slot`), **not** the row id — `id` only counts
upward and would leave the band after 128 rows. Freed slots are reused. An
index at or beyond `maxPatients` throws rather than wrapping, because wrapping
is exactly the collision being prevented.

**IDs repeat every 32 days per patient, and that is deliberate.** We never
schedule more than `reminderWindowDays` (7) ahead, so a repeated ID is never
pending twice; `planWindow` asserts the window stays under the cycle. The
4096-day cycle this replaced was 11 years of space for something that lives
for days — that waste is now the patient dimension.

| Band | Range | Owner |
|---|---|---|
| Dose reminders | `1_000_000` – `6_898_239` | **Phase 1**, live. `doseIdBase` / `doseIdLimit` / `isDoseId()` in `reminder_plan.dart`. 128 patients × 46,080 |
| Escalation | `10_000_000` – `15_898_239` | **Phase 4**, reserved and unused. Use base `10_000_000` and the same formula |
| Snooze | `20_000_000` – `25_898_239` | live. `snoozeIdBase` / `snoozeIdFor()` / `isSnoozeId()`. Derived from the **original** dose slot, not the snooze time — so a snooze can never overwrite a real dose that happens to fall on the same minute, and «أخدته» cancels it without storing anything |
| — | everything else | unclaimed; take the next free band at a `10_000_000` boundary and add an `isXxxId()` guard beside `isDoseId()` |

Band width is unchanged at 5,898,240 — `128 × 46,080` is exactly the old
`4096 × 1440`. The gap between bands is deliberate slack, and every band stays
far below the 32-bit ceiling Android imposes on notification IDs
(`2_147_483_647`).

**iOS keeps only 64 pending local notifications per app and silently drops
the rest** — no error, no warning. So the window is capped, not fixed:
`maxPendingReminders` is 48, leaving 16 under the limit for Phase 4's
escalation. `planWindow` sorts and keeps the **nearest** 48, so the horizon
shortens by itself as medications accumulate — a patient on one drug gets the
full 7 days, one on six drugs three times daily gets about two and a half.
Every app launch calls `rescheduleAll()`, which re-extends the window from the
new "now". The cap applies on Android too: one behaviour on both platforms
beats "works on my Android".

**The window must renew without the app ever being opened.** The patient
has no reason to open it — the app exists to remind *him*. At 48 pending and
12 doses a day that is four days of coverage; on day five reminders would
silently stop for exactly the person who needs them most. So every
confirmation re-extends the window (`ReminderScheduler.afterConfirmation`:
cancel the slot first — rule 5 — then `rescheduleAll()`), and the
notification itself carries «أخدته» / «فكّرني بعدين» buttons. Those actions
show no UI: the OS wakes the app in a background isolate and
`onBackgroundNotificationAction` (`lib/app/bootstrap.dart`,
`@pragma('vm:entry-point')`) opens the database, records the dose and
re-emits the window. `NotificationActionHandler` is the testable core;
`test/data/notification_actions_test.dart` drives a week of lock-screen
confirmations with no widget pumped and asserts coverage keeps moving.

**A dose confirmed early must not be re-scheduled.** 2:00 PM taken at 1:50 is
still "in the future" by the clock. `planWindow` takes the set of done
`(scheduleId, routineDay)` keys (`doneKey`, read from `dose_events`) and drops
them; a grouped reminder keeps its remaining doses. The handler also
materialises the day's events before marking, because «يومك» — which
normally does that — may not have run that day.

**Rescheduling only ever cancels inside its own band.** `ReminderScheduler`
diffs the planned IDs against `pending()` and cancels the stale ones filtered
through `isDoseId`. `cancelReminderAt(at)` is the one exception by design: it
cancels the dose ID *and* the snooze ID of that single slot, because a
confirmation must silence everything that slot could still ring. A missed
critical dose escalates to the caregiver, and `cancelAll()` would silently take
that escalation down while merely rebuilding a routine — so it is never used. Any new feature that schedules notifications
must claim a band and filter cancellations by it the same way.

---

## Phase 3 — identity (optional, NEVER a gate)

The app is complete with no account: onboarding → scan → reminders all work
offline forever. Identity exists only because escalation needs the son's
phone. Its single door is «اربط ابني» on «يومك». If a sign-in screen ever
appears at startup, that is a bug by definition —
`test/app/root_test.dart` has a loudly-named guard test for it.

- `lib/data/auth/` is the ONLY place allowed to import `supabase_flutter`
  or `google_sign_in`. Everything else sees the `AuthService` interface
  (`authState`, `currentUser`, `signInToLink`, `signOut`) and
  `FakkarniUser` (with `isAnonymous` from the JWT `is_anonymous` claim —
  unused yet, upgrade rounds will need it). The live implementation is
  `AnonymousAuthService` (see «دين تقني»); `GoogleAuthService` is already
  written as a dormant sibling, and **Apple arrives the same way** — a new
  file on the same interface, never a refactor. Email OTP was removed from
  the product entirely; do not rebuild it.
- `signInToLink()` (currently `signInAnonymously`) is called from exactly
  one line: the SignInScreen button handler. Never from `main()`, startup,
  a splash, or an eager provider — a fresh install reaches «يومك» with NO
  Supabase session. The guard test in `root_test.dart` runs with auth
  *configured* and asserts zero sign-in calls and no session at launch, so
  it cannot become trivially true.
- Config via `--dart-define` only, like `GEMINI_API_KEY`: `SUPABASE_URL`,
  `SUPABASE_ANON_KEY`, `GOOGLE_SERVER_CLIENT_ID` (the Web client ID —
  Supabase's audience), `GOOGLE_IOS_CLIENT_ID`. Missing → app runs fully,
  the sign-in screen names what's missing. `initSupabaseAuth()` never
  throws and never blocks startup; failures log and return null.
- Errors reach the screen only as the four agreed Arabic states; user
  cancellation is silent; an expired refresh token lands on signed-out
  silently. Raw SDK strings never render.
- `google_sign_in` is v7: `initialize()` once then `authenticate()`, which
  throws `GoogleSignInException` with a code (`canceled` → silent). The API
  was read from the installed source — keep doing that here.
- Sign-out is local-scope on purpose (must work offline); server-side
  revocation comes with the sessions round.
- Out of scope so far: tables, RLS, sync, invite codes, care
  relationships, anonymous auth.

**The one gate through the wall is `redeem_invite`** (round 3.3).
`care_relationships` and `invite_codes` have NO insert/update policies —
that absence is the security model: any INSERT policy would let a key
holder who learned one patient_uuid grant himself an 'accepted' link.
Creation and redemption happen only inside two SECURITY DEFINER functions
(`create_invite` / `redeem_invite`, `search_path=''`, authenticated-only) —
the redeemer under RLS can neither read the code row, insert the link, nor
burn the code, and the function does all three atomically. Error tokens
(`invalid_code` / `own_code` / `already_linked`) are mapped to Arabic in
`lib/data/care/` — server text never renders. Roles emerge from data: a
redeemer is a caregiver for that patient, a device with a local patient row
is a patient; there is no role column. The only sync write so far is the
patient row upsert (uuid, owner_id, name) right before showing a code.
Known accepted risk: a 6-digit code space is brute-forceable in principle;
mitigations today are the 15-minute expiry and one live code per patient —
rate limiting is future work.

**Sync is one-way, silent, and derived.** Local drift is the source of
truth; the cloud is a copy; only the owner's device writes; nothing pulls
into drift (3.5 reads Supabase directly) — so there is no merge code, on
purpose. Dirtiness is derived (`synced_at_ms IS NULL OR < updated_at_ms`,
epoch **milliseconds** so a same-second edit during a push stays dirty),
and `updated_at_ms` is maintained by SQLite triggers created idempotently
in `beforeOpen` (self-healing after any table rebuild) — never by call
sites. The trigger fires only `WHEN NEW.synced_at_ms IS OLD.synced_at_ms`
so the push's own marking never re-dirties rows. `SyncService.push()` is
parent-first, marks `synced_at_ms` with the pushed `updated_at_ms` (never
now()), and is a silent no-op unless signed in AND linked
(`confirmLinked()` fires once from the link screen). Triggers: foreground,
3s-debounced local writes via `db.tableUpdates()`, connectivity restored.
Never a timer, never an error surfaced to the user. Wire times are UTC ISO.
**Migration steps normalize tables (alterTable) only in the LAST step of
the chain** — an intermediate normalization builds tomorrow's shape from
yesterday's columns and breaks old upgrade paths (bitten twice now).

**The cloud schema's only wall is RLS** (`supabase/` — SQL only, run by
hand in the SQL editor, order: 0001 → 0002 → tests). The publishable key
ships in the binary, so every table has RLS enabled as its first statement
and `anon` is stripped of table privileges entirely. All access checks
route through one SECURITY DEFINER function,
`private.can_access_patient` — patients' visibility depends on
care_relationships and vice versa, and direct policies would recurse
("infinite recursion detected in policy"). Always `(select auth.uid())`,
never bare. Cloud PKs are the device-minted uuids; local int ids have no
cloud column. Caregivers are read-only until escalation adds one narrow
UPDATE policy. After ANY schema change run `tests/rls_test.sql` and the
zero-rows `rowsecurity=false` check in `supabase/README.md`.

---

## دين تقني

Debts we took on knowingly. Each one blocks something specific — check this
list before any store submission.

### Decision: phone calls are cancelled (not deferred)

Automated voice calls to the caregiver are **out of the product**. Decided
deliberately, not forgotten — do not reintroduce them, and do not propose
them in a plan without the owner asking first.

Why: a paid telephony provider working in Egypt, per-call cost, Arabic TTS,
DTMF confirmation and call-state webhooks were the single largest source of
risk and delay in the plan, for a feature that could not ship free.

What replaces it: escalation ends at a **push notification to the caregiver**.

What this costs us, stated honestly so nobody is surprised later: push is the
same channel the patient already missed, so the ladder is weaker than a call.
That makes the mechanics of the caregiver alert load-bearing — see the
escalation rules below. It is not "just another notification"; it is the last
rung, and it must behave like one.

Consequences to handle:
- The executive plan given to management describes a **paid subscription for
  the calls feature**. That subscription now has no feature behind it. The
  plan document needs updating before it is shown again.
- `escalations.channel` stays in the schema with value `push`. It is a
  generic audit column, not a placeholder for calls.
- iOS **Critical Alerts** entitlement (bypasses silent mode and Focus) is now
  the only remaining way to make the caregiver alert harder to miss. It needs
  Apple's approval and the paid developer account. Request it before launch.

0. **Sync has no deletes and no second owner device — yet.** Deletes ship
   as soft-delete (`deleted_at`) with the first feature that needs one;
   a second device for the same owner ships as last-write-wins by
   `updated_at`. Neither exists today, and nothing may pretend to handle
   them until they do. A dose confirmed from the lock screen stays dirty
   until the next app open/foreground (the background isolate builds no
   SyncService).
1. **Anonymous sign-in is a development stand-in ONLY.** An anonymous user
   is bound to one device and is lost when app data is cleared. It must be
   upgraded via `linkIdentity` to Google before any store submission.
   **Shipping with anonymous auth is forbidden.**
2. **Sign in with Apple is mandatory before any iOS App Store submission**
   once Google is offered (Guideline 4.8). Blocked until the paid Apple
   Developer account exists. It lands as a sibling `AuthService` file.
3. **Huawei / no-GMS devices cannot use Google Sign-In** — a real segment
   in Egypt. May require adding an email provider later; `AuthService`
   must stay open to it (which is why the interface is provider-neutral).

---

## Design reference

All 33 screen mockups live in `screenshots/` as numbered PNGs
(`01-splash.png` … `33-settings.png`). Look at the relevant file before
building a screen, and match its layout, hierarchy and spacing.

**They are a reference for appearance, not for structure.** Do not translate
the mockup's HTML/CSS into Flutter literally — build with native Flutter
widgets and take every colour and size from `class F` in
`lib/core/theme/tokens.dart`, never from a value eyeballed off the image.

**Where a mockup and the UI rules above disagree, the rules win** — especially
minimum text size and tap targets. Say so instead of silently following the
image.

---

## Commands

```bash
flutter test                       # everything
flutter test test/domain/          # engine only, ~1 second
flutter run                        # needs a REAL device for notification testing
flutter analyze
```

Flutter 3.47.1 / Dart 3.13.1 at `~/develop/flutter`. There is an older Flutter
elsewhere on this machine — always use the one on PATH after `.zshrc` setup.

---

## Current state

**Phase 1 is complete and verified on a physical iPhone** — reminders fire
with the app fully closed, offline, and across a reboot.

**Done (Phase 1)**
- Scheduling engine + tests (offsets, after-midnight bedtime, Ramadan,
  grouping, `once` repeat, open-ended duration, next-reminder, fixed times)
- Brand tokens (`class F`)
- `NotificationService` — timezone-aware scheduling, exact-alarm handling
- Android manifest permissions, receivers, core library desugaring
- drift database + repositories, schema v3 with in-place migrations
- Engine → notifications: derived IDs, 7-day / 48-pending window,
  band-filtered reconcile, `rescheduleAll()` on every launch
- Screens: routine onboarding, add medication (anchor default + fixed-time
  escape hatch), «يومك», reminder, edit routine («عدّل يومك»)
- Notification tap → `ReminderScreen` (also on cold launch, waits for the
  routine to load). Payload = routine day + schedule IDs, never a time.
- Snooze («فكّرني بعد ربع ساعة») in its own ID band
- Notification action buttons («أخدته» / «فكّرني بعدين») handled in a
  background isolate; every confirmation re-extends the window; early
  confirmations are excluded from re-scheduling

**Phase 2 — read a paper prescription (built, needs a real-photo pass)**
- `lib/ai/`: config, reading model with per-field confidence, Gemini REST
  reader. Threshold 0.8; below it a field is gold «محتاج تحديد».
- Scan screen (framing advice → «صوّر الروشتة» 64px / «اختار من الصور» 56px,
  same size constraints for both) and review screen with per-line
  «أعدّل السطر ده», equal-weight «أعدّل»/«تمام», «صوّر تاني» — which returns
  to the scan screen so both sources are offered again, never auto-opening
  the camera.
  «تمام» writes each clear line (one schedule per timing) then `rescheduleAll`.
- Editor accepts prefilled values and now has an optional amount field;
  the offset stepper follows the chip (30 before meals, 15 before sleep).
- Unknown amount is non-blocking: saved as `amountUnknown`, surfaced on
  «يومك» as «اسأل الصيدلي عن جرعة …», which opens `EditMedicationScreen`.
- «يومك» lists «أدويتك» (mockup 09 rows: name, amount · rule); each row
  opens `EditMedicationScreen`: set the amount (the only place that clears
  `amountUnknown`, by a value a human typed) or stop the medication —
  two-step confirm, ink not red, `stopMedication` + `rescheduleAll`.
- Model pinned to `gemini-3.6-flash` with a one-shot, loudly-logged fallback
  to `gemini-flash-latest` on `404 NOT_FOUND`.
- Not yet done on hardware: a real handwritten prescription through the
  live API — that is where the image-size numbers and the prompt get tuned.

**Round 3.2a — stable row identity (built)**
- `uuid` on all six tables, v4 backfilled per row, schema v5. Verified by
  SchemaVerifier (v4→v5) and the hand-written v2-file test (v2→v5).

**Round 3.4 — one-way sync, father's device → cloud (built)**
- drift v6: `updated_at_ms`/`synced_at_ms` on every SyncIdentity table,
  SQLite triggers in beforeOpen, SchemaVerifier-proven migration (rows
  survive, everything starts dirty so the first push uploads history).
- `lib/data/sync/`: SyncService (dirty queries with uuid-joins, batched
  upsert-on-uuid, silent failure policy) + SupabaseSyncRemote (injects
  owner_id on patients). Cloud 0004: server-side updated_at (moddatetime).

**Round 3.3 — invite code + care circle (built)**
- SQL: `invite_codes` + `create_invite`/`redeem_invite` (the one gate);
  rls_test.sql extended and still the authority. Dart: `CareCircleService`
  (interface + Supabase impl in lib/data/care/), father's huge 3-3 western
  code screen, son's 6-digit redeem screen, patient-row upsert — the only
  sync write. Device check: father shows code, son (simulator) redeems,
  one accepted care_relationships row, code marked used.

**Phase 3.1 — identity plumbing (built)**
- `AuthService` + `AnonymousAuthService` (live) + `GoogleAuthService`
  (dormant sibling); `SignInScreen` behind «اربط ابني»; guard tests prove
  auth is not a gate. Real-device check: tap «اربط ابني» with
  SUPABASE_URL/SUPABASE_ANON_KEY set → user appears in Supabase Auth.

**Next**
1. Photograph a real handwritten prescription with the key set; tune
   `maxWidth`/`imageQuality` and the prompt from what actually fails
2. Re-run the `/device` checklist for the action buttons specifically: tap
   «أخدته» on the lock screen with the app terminated, then check
   `pending()` grew (Android background isolate + iOS category actions were
   not part of the first device pass)
2. Stop / edit a medication from «يومك» (`stopMedication` exists in the
   repository, no screen calls it)
3. Phase 4 groundwork: escalation band, caregiver contact, the ladder

---

## Never do

- Add a dependency to `lib/domain/`
- Persist a resolved clock time for an anchor dose, make `FixedTiming` the
  default, or put a time column on `dose_schedules`
- Wipe or recreate the database to change the schema — write a migration and
  a case in `migration_test.dart`
- Schedule a notification straight from an unconfirmed AI result
- Call `cancelAll()` — it reaches across every band, including Phase 4's
  escalation. Cancel by ID, filtered to your own band
- Allocate or persist a notification ID; derive it from the slot instead
- Use `fullScreenIntent` or the `USE_EXACT_ALARM` permission — Google Play
  restricts both to alarm/calling apps and will reject the review.
  Use `SCHEDULE_EXACT_ALARM` requested at runtime instead.
- Write formal MSA in the UI
- Invent a medication duration, dosage or timing — this applies to the
  Gemini prompt as much as to the code
- Hardcode an API key, put one in a tracked file, or call Gemini with an
  empty key
