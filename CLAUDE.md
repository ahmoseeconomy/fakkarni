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

5. **A confirmation cancels every rung that has not yet fired — on the
   device and on the server — immediately, at any stage.** No exceptions
   and no "unless", including after the caregiver has already been
   alerted: the next rung dies the moment he confirms. A few seconds of
   lag here means needlessly worrying the son, which is worse than a late
   alert.
   The one thing this rule does **not** claim is the impossible. An alert
   already delivered to the son's phone is not recalled — there is no
   unsend, and both ways of faking one are worse than the alert itself.
   A second "never mind" push spends the channel that has to stay
   meaningful, and silently deleting a notification he may already have
   read turns a worrying message into a vanishing one. The repair is a
   correct view, not a deletion: his next refresh shows the dose as taken.
   Never build a recall path; if you think you need one, re-read this.

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
- **Red belongs to the two emergency screens and to nothing else** —
  «معلومات الطوارئ» (`F.redDeep` ground) and «بطاقة الطوارئ», both in
  `lib/features/emergency/`, with `F.red` on the ambulance button. The
  mockups also spend red on the `طوارئ` shortcut in the top bar; ours is
  ink-outlined, because red on any other screen is wrong — including the
  door to the emergency screens. Never use red for an error, a warning, a
  validation message, or a missed dose. A missed dose uses gold and neutral
  wording — he forgot, he did not fail. `test/app/red_only_in_emergency_test.dart`
  reads `lib/` and fails on any red token or hex outside that folder.
- **Gold (`F.gold`) means one thing: "this needs your attention now."** A
  dose that needs taking now, the state you are currently on, and a field the
  AI is unsure about (the review row's gold edge, «مش متأكد من دي — راجعها»)
  — all three are that one meaning. Do not
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
  domain/escalation/          PURE DART — escalation_ladder.dart: rungs
                              +15/+30, graceWindow 45, serverGraceWindow 60,
                              syncSlack 15, ladderFor, isPastGrace
  ai/                         Phase 2 — gemini_config (key from --dart-define),
                              prescription_reading (pure model + responseSchema),
                              prescription_reader (Gemini REST, http.Client injectable)
  core/theme/tokens.dart      brand colours + elderly-first sizing (class F)
  core/notifications/         NotificationService — local scheduling; tap → lastPayload
  data/db/                    drift (SQLite) v15: patients (sex, age — local),
                              day_routines, routine_backups (v7, local),
                              device_preferences (v9, local: elder mode +
                              the +15/+30 rung switches), emergency_profile
                              (v10, local: SyncIdentity columns but never
                              pushed), records (v11, local, soft delete),
                              readings + lab_results (v12, local),
                              visit_questions (v14, local),
                              dose_schedules.active_from (v15, local),
                              medications (amount_unknown), dose_schedules
                              (timing_kind), fixed_timings, dose_events — every
                              synced table carries a device-minted `uuid`
                              (SyncIdentity mixin)
  data/repositories/          routine / medication / dose_event
  data/services/              reminder_plan (pure: IDs, window, payload,
                              planEscalations), reminder_scheduler (engine →
                              sink; materialise → sweepMissed → plan), reminder_sink
                              notification_actions (lock-screen «أخدته»/«فكّرني بعدين»)
  app/                        AppScope (services), AppRoot (onboarding | today,
                              opens ReminderScreen on tap), bootstrap.dart
                              (buildServices + background action entry point)
  features/onboarding/        5 routine questions (mockup 22): one per
                              screen, 3 preset chips above the wheel,
                              «مش متأكد» → DayRoutine.fallback, 5 dots
  features/medication/        dose_editor (mockup 23 — the ONE timing editor:
                              8 anchor chips, −/+ stepper, gold preview, fixed
                              link last); add_medication (mockup 20 fields →
                              one DoseEditor per timing, saved only after the
                              last); EditMedicationScreen — amount, per-dose
                              «عدّل» → DoseEditor (updateTiming), stop (two-step)
  features/today/             home (greeting, «الآن», 48h, water) + day rail;
                              dose_actions (confirm/snooze shared with elder)
  features/elder/             ElderHomeScreen — one dose card, «تم ✅» 80
  features/routine/           EditRoutineScreen — change any anchor after onboarding
  features/settings/          SettingsScreen + NotificationsScreen (rung switches)
  features/link/              SignInScreen — the one door to identity («اربط ابني»)
  features/entry/             EntryScreen «مين ماسك التليفون؟» (D4) — routes only
  features/care/              CaregiverScreen «متابعة {الاسم}» — the son's
                              read-only home (CaregiverShell: «متابعة» +
                              «الإعدادات»), straight from Supabase
  domain/wording/             rule_wording — «الفطار − ٣٠ د» text shared by
                              the scheduler and the son's side (no scheduling
                              import there)
  data/auth/                  AuthService interface + GoogleAuthService +
                              supabase_init (initSupabaseAuth for the app,
                              initSupabaseForIsolate for the background wake-up)
  data/push/                  PushTokens / DeviceTokenSource / PushTokenRemote
                              (interfaces) + PushTokenService (pure decision
                              logic, tested with fakes) + firebase_token_source
                              (the ONLY firebase import in the app) +
                              supabase_push_tokens (claim_device_token)
  features/scan/              ScanPrescriptionScreen (advice → «صوّر الروشتة» /
                              «اختار من الصور», one image_picker path for both)
                              + ReviewPrescriptionScreen «الذكاء يقترح، وأنت تؤكّد»
  features/reminder/          ReminderScreen (mockup 10) — تم التناول ✅ / تأجيل ١٥ د ⏰ /
                              تخطّي, four-rung ladder from domain constants
test/                         655 passing
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
| Escalation rung 1 (+15) | `10_000_000` – `15_898_239` | **Phase 4.1**, live. `escalationFirstIdBase` / `escalationIdFor(at, rung)` / `isEscalationId()`. Derived from the **original** dose slot like snooze |
| Snooze | `20_000_000` – `25_898_239` | live. `snoozeIdBase` / `snoozeIdFor()` / `isSnoozeId()`. Derived from the **original** dose slot, not the snooze time — so a snooze can never overwrite a real dose that happens to fall on the same minute, and «أخدته» cancels it without storing anything |
| Escalation rung 2 (+30) | `30_000_000` – `35_898_239` | **Phase 4.1**, live. `escalationSecondIdBase`. One band per rung because a band holds exactly one ID per (patient, slot) — a second rung needs a second band |
| Fasting reminder | `40_000_000` – `45_898_239` | **D3.7**, live. `fastingIdBase` / `fastingIdFor(recordId)` / `isFastingId()`. Derived from the `records` row id (not a slot — one reminder per checkup cycle), throws past the band. **Not** in `isRescheduledId`: rebuilding doses never cancels it, and a dose confirmation never touches it. `test/data/checkup_fasting_test.dart` proves it overlaps no dose band — mutation-checked: moving the base into the dose band fails three tests |
| — | everything else | unclaimed; take the next free band at a `10_000_000` boundary (`50_000_000` is next) and add an `isXxxId()` guard beside `isDoseId()` |

Band width is unchanged at 5,898,240 — `128 × 46,080` is exactly the old
`4096 × 1440`. The gap between bands is deliberate slack, and every band stays
far below the 32-bit ceiling Android imposes on notification IDs
(`2_147_483_647`).

**iOS keeps only 64 pending local notifications per app and silently drops
the rest** — no error, no warning. So the window is capped, not fixed:
`maxPendingReminders` is 46 (48 until D3.7); the remaining 18 are
`maxPendingEscalations` (14 = the nearest 7 reminders × 2 rungs),
`snoozePendingSlack` (2) and `fastingPendingSlack` (2 — at most two fasting
reminders exist at once, and the button says so), so dose + ladder + a
snooze + fasting never reach 65. `planWindow` sorts and keeps the **nearest** 48, so the horizon
shortens by itself as medications accumulate — a patient on one drug gets the
full 7 days, one on six drugs three times daily gets about two and a half.
Every app launch calls `rescheduleAll()`, which re-extends the window from the
new "now". The cap applies on Android too: one behaviour on both platforms
beats "works on my Android".

**Two isolates write this SQLite file, so the connection sets WAL and a
busy timeout — in one place, for every opener.** The app runs
`rescheduleAll` as it starts; a lock-screen «أخدته» wakes a separate
isolate that opens the *same file* and writes. That is the normal case,
not a rare one — the same tap can do both. With SQLite's defaults the
loser of the race fails instantly with
`SqliteException(5): database is locked` on `BEGIN IMMEDIATE`. WAL stops a
reader blocking a writer; **`busy_timeout` is the line that actually fixes
it**, because WAL does nothing for two *writers* — the default is to give
up at once rather than wait. `busy_timeout` is per-connection and is not
stored in the file, so it must be set by every isolate: that is why it
lives in `prepareDatabase` inside `connection.dart`, which everything goes
through. `openDatabaseFile` is exposed so tests open the file exactly the
way the device does. `test/data/db/concurrent_write_test.dart` reproduces
the original exception when the pragmas are removed.

**In the lock-screen handler, the promise is the dose row and the cancel;
everything after is a courtesy.** Recording the confirmation now uses
`DoseEventRepository.confirmDose` — one row seeded if missing and its state
written, a two-statement transaction — and it runs *first*. It used to be
`materializeDay` (the whole day, one large transaction) and only then
`markTaken`, so a lock conflict on a write that is **not** the promise
destroyed the confirmation itself. `rescheduleAll` still runs from the
isolate, because nothing else renews coverage for a patient who never opens
the app — but it is demoted to a courtesy: wrapped, logged loudly, and
never able to undo a confirmation already written. The cloud push was
already last and stays there.

**A confirmation that fails must never look like one that succeeded.** iOS
removes the notification the moment the button is tapped, whether our write
worked or not — so a swallowed error leaves the patient certain he
confirmed while nothing was recorded. The handler therefore **throws** when
the promise fails and only swallows courtesies.
`test/data/notification_actions_test.dart` pins both directions, and the
throwing case was mutation-checked: wrap the promise in a `try`/`catch` and
it goes red.

**iOS runs notification actions in a SECOND Flutter engine, and that
engine gets no plugins unless `AppDelegate` says so.** A tap on «أخدته»
with the app terminated does not reuse the main engine — the plugin spawns
a separate one (`FlutterEngineManager.m`: `NSAssert(registerPlugins != nil)`
then `registerPlugins(backgroundEngine)`). Without
`FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` in
`didInitializeImplicitFlutterEngine`, that engine has zero plugin
registrations, so `onBackgroundNotificationAction` dies **before its first
line**: no drift, no path_provider, not even a `debugPrint`. The symptom
is exactly nothing from Dart while Console.app shows SpringBoard handling
the action normally — which reads like a Dart bug and is not one.
Registering the main engine (`GeneratedPluginRegistrant.register(with:
engineBridge.pluginRegistry)`) is a **separate** line and both are needed;
this app is on the UIScene lifecycle, so both live in
`didInitializeImplicitFlutterEngine`, not `didFinishLaunchingWithOptions`.
Android needs no equivalent. The two diagnostic `debugPrint`s that found
this — at the isolate entry point and in `_onTap` — are kept on purpose:
they are the only visibility into a path no test can reach.

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

**A dose that falls before its rule existed was never a dose.**
`dose_schedules.active_from` is the instant a rule took effect — written by
`MedicationRepository` (injectable `clock`) when the rule is created **and**
when `updateTiming` changes it; null on rows from before v15 (active since
forever — no invented time). It is **not** a dose time (the ban on a time
column on `dose_schedules` is about resolved dose times; the column test
allows this one name) and it is **not** `updatedAtMs`, which belongs to sync.
`materializeDay` — the one place every caller goes through — makes no row
for a dose whose instant is before `active_from`, and `rescheduleAll` adds
those doses to `done` so no escalation rung rings for them. A medicine added
at 11:17 therefore shows no «نسيتها؟» for its 7:00 dose, and tomorrow's 7:00
is materialised as usual. **A timing edited to an earlier time never deletes
the existing `pending` row**: that row may already be in the cloud, sync has
no deletes (debt 1), and a ghost `pending` there would alert the son. The
device writes `DoseState.superseded` («القاعدة اتغيّرت») instead; it is
pushed like any state, `due_escalations` ignores it (only `pending` is
chosen), `watchDay`/`watchBetween` and the caregiver query hide it, and an
edit back to a time still ahead revives it to `pending`. Cloud:
`0010_dose_superseded.sql` widens the state check — **it must run before a
v15 build reaches a linked phone**, or the old check rejects the row and the
whole `dose_events` batch fails silently. Tests: `test/data/active_from_test.dart`
(new medicine, new dose on an old medicine, earlier edit, the ladder, the
reverse case, pre-v15 null) — mutation-checked three ways. Test fixtures
seed medicines with `seededLongAgo` (`test/support/seeded_clock.dart`);
tests about `active_from` inject their own clock.

**A dose confirmed early must not be re-scheduled.** 2:00 PM taken at 1:50 is
still "in the future" by the clock. `planWindow` takes the set of done
`(scheduleId, routineDay)` keys (`doneKey`, read from `dose_events`) and drops
them; a grouped reminder keeps its remaining doses. The handler also
materialises the day's events before marking, because «يومك» — which
normally does that — may not have run that day.

**Rescheduling only ever cancels inside its own bands.** `ReminderScheduler`
diffs the planned IDs against `pending()` and cancels the stale ones filtered
through `isRescheduledId` (dose + escalation; snooze is deliberately outside —
it is cancelled by a confirmation, never by a rebuild). `cancelReminderAt(at)`
is the one exception by design: it cancels the dose ID, the snooze ID *and*
both escalation rung IDs of that single slot, because a
confirmation must silence everything that slot could still ring. A missed
critical dose escalates to the caregiver, and `cancelAll()` would silently take
that escalation down while merely rebuilding a routine — so it is never used. Any new feature that schedules notifications
must claim a band and filter cancellations by it the same way.

---

## Phase 3 — identity (optional, NEVER a gate)

The app is complete with no account: onboarding → scan → reminders all work
offline forever. Identity exists only because escalation needs the son's
phone. It has two doors, both behind a tap: «اربط ابني» on the patient's
«العائلة» tab, and «ابني أو والدي بعتلي كود» on the D4 entry screen — which
is a **question, not a sign-in** (no session, no call until that card is
tapped, and then only through SignInScreen's button). If a sign-in screen
ever appears at startup, that is a bug by definition —
`test/app/root_test.dart` has loudly-named guard tests for it.

- **An SDK import lives in a `supabase_*` / `firebase_*` file behind an
  interface, and nowhere else.** `lib/data/auth/` was once the only place
  allowed to import `supabase_flutter`; that stopped being true in 3.3 and
  this line stayed wrong until round 4.2b part 2. What actually holds is
  the shape: the app sees `AuthService`, `SyncRemote`, `CaregiverRemote`,
  `CareCircleService`, `PushTokenRemote`, `DeviceTokenSource`, and the SDK
  sits in one named file implementing it. `firebase_messaging` appears in
  exactly one file (`lib/data/push/firebase_token_source.dart`), and
  `main.dart` imports neither SDK. Everything else sees the `AuthService` interface
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

**The background isolate pushes too, and cloud always comes last**
(round 4.2a). A lock-screen «أخدته» is the most common confirmation path
for a 72-year-old, and since 4.1 the same wake-up also materialises days
and writes «اتنست». None of it reached the cloud until the next
foreground, which the patient has no reason to trigger — so 4.2b's
server-side scan would alert the son about a dose already taken.
`NotificationActionHandler` now ends with `sync?.pushOnce()`, **after**
the local write and after `rescheduleAll` has cancelled the slot's
notifications. That order is rule 5: a network call placed before the
cancels would leave the +30 rung armed on a bad connection and nag a man
who already took his pill. The local write and the cancels are the
promise; the push is a courtesy that is allowed to fail. `pushOnce` is
one attempt with a `backgroundPushTimeout` (5s) and never throws — a
timeout frees us, not the request, which is enough because everything
that matters already happened. Unpushed rows stay dirty by construction
(`synced_at_ms` is marked only after a successful upsert).

**Supabase can be initialised inside the background isolate** — verified
against the installed sources, not assumed (`supabase_flutter` 2.17.2,
`gotrue` 2.27.2). `Supabase.initialize` awaits `SupabaseAuth.initialize`,
which reads SharedPreferences and calls `setInitialSession`, so
`currentUser` is ready after the await with no network; the unawaited
`recoverSession()` is only a proactive refresh. Every PostgREST call takes
its token from `getSession()`, which refreshes an expired one first and
throws rather than sending it. Two settings are load-bearing in
`initSupabaseForIsolate`: `detectSessionInUri: false` (no app_links
observer in a background wake-up), and `autoRefreshToken` left at its
default `true`, stopped by hand on shutdown. **Passing `false` is the
trap**: with auto-refresh off, an expired session sends `recoverSession`
into a local `_signOut`, so the isolate would sign the patient out of the
whole app while recording a dose. The shutdown is skipped when
`_initialisedByApp` is set, so if the background path ever runs inside the
app's own isolate it cannot stop a live client's token refresh. The init
itself carries `isolateCloudInitTimeout` (2s) because it runs *before* the
local write: it is local plugin-channel work that should finish instantly,
but a channel that hangs there would delay recording the dose and
cancelling the ladder, and those are the promise.

**The push token is cleared BEFORE sign-out, never after.** Deleting the
`device_tokens` row needs the session that owns it; call `signOut()` first
and the row survives in the cloud, so a phone that has left the account
keeps receiving alerts about a patient who is now a stranger to it.
`PushTokens` is injected into `SignInScreen` like `AuthService` —
deliberately *not* pulled from `AppScope` — because sign-out must work
whether or not a scope sits above it. Registration is the mirror image: on
every sign-in through the auth stream, *and* eagerly right after linking,
because the son may close the app at once and his father's first missed
dose can be an hour later. Failures are silent and logged like sync; the
retry is the next sign-in, token rotation or launch. The one thing never
done is deleting the Firebase token itself — it belongs to the install,
not the account, and reattaching it to a new owner is what
`claim_device_token` is for.

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
yesterday's columns and breaks old upgrade paths (bitten **three** times
now). In code that means: the `if (from < 6)` normalization block sits at
the very **end** of `onUpgrade`, after every later step's columns exist.
v8 found it the hard way — the block used to live inside the v6 step,
rebuilt `patients` on a definition that already had `sex`, and failed
every upgrade from v5 or older until it moved. **Any new column goes in
its own `from < N` step ABOVE that block, added with an existence check.**

## Phase 4 — the escalation ladder

**Every dose escalates; there is no "critical" flag** (decided 2026-09-02).
Choosing which drug is critical is a clinical judgment rule 6 forbids, and
mockup 26 already says the miss alert «لا يمكن إيقافه». Where this file
says "critical dose" read "any dose". If a per-medication toggle is ever
wanted it is worded operationally («لو نسيها، نبّه ابنك»), default on, and
it only *filters* `planEscalations` — the ladder itself does not change.

**The ladder is pure and pre-scheduled** (`lib/domain/escalation/`). Rungs
are +15 (`EscalationRung.first`) and +30 (`second`) from the *original* dose
minute, never from the previous rung; `graceWindow` is 45. Every rung is a
local notification scheduled ahead of time, because neither OS runs our
code when a notification merely fires — only when the user touches it. A
rung carries the dose's own payload and the same «أخدته»/«فكّرني بعدين»
buttons, so acting on a rung is acting on the dose. Android rungs go out on
the `fakkarni_escalation` channel (vibration pattern, own volume slider);
iOS stays `timeSensitive` until the Critical Alerts entitlement exists.

**The ladder window is built from now − 45, not from now.** A dose that
rang at 8:00 is gone from `planWindow(from: 8:10)`; if the ladder were
derived from that plan, opening the app at 8:10 would cancel the 8:15 and
8:30 rungs as "stale" — the app would silence the ladder of exactly the
dose in progress. So `rescheduleAll` plans escalations from a second
`planWindow` whose `from` is shifted back by `graceWindow`, then drops
rungs already in the past. Only the nearest 7 reminders get a ladder; the
window renews on every confirmation and launch like the dose window.

**«اتنست» is a grace decision, written by the device, reversible.**
`rescheduleAll` first materialises yesterday's and today's routine days
(so a day the app never opened still has rows — and yesterday's bedtime
dose is counted the next morning), then `sweepMissed(now)` writes
`DoseState.missed` on every pending row whose `scheduled_at + 45 ≤ now`.
`actedAt` stays null: nobody acted, and the row says so. «أخدته» after that
overwrites it — he forgot, then remembered. `rescheduleAll` runs on launch,
foreground resume, every confirmation and every lock-screen action, so the
decision is taken at every wake-up the OS gives us; there is no timer.
«جدول النهاردة» shows «نسيتها؟» on the pinned card and «لسه ما اتأكدتش»
on the rail card — the same line for an overdue dose and a swept `missed`
one, with the same gold edge as a dose still to come (gold = «دي لسه
عايزاك»; never grey, never red). «أخدته» on the pinned card is the only
primary; tapping a rail card opens its `ReminderScreen`. A taken dose
collapses to a ✓ line and never leaves the rail. The son's screen renders `missed` verbatim as
«اتنست — لسه ما اتأكدتش» in gold — reporting the father's device's
decision, still not judging.

**`pending` and `missed` both mean «ما اتأخدتش».** The difference is who
marked the row — nobody yet, or the device after its 45-minute grace — not
a different medical state, and never a reason to stay silent. So the
server escalates on both (`0011_escalate_missed.sql`). Until 0011 it chose
`pending` only, on the theory that «اتنست» was "a decision already taken";
but the device writes it at +45 on any wake-up (opening the app, tapping
another dose's notification) and sync lifts it within seconds, so at +60
the scan found nothing and the son was never told — in the **common** case,
because the phone is in its owner's hand. `taken` (rule 5), `skipped` (a
human's decision, not forgetting) and `superseded` (0010) never escalate.
A row flipping `pending` → `missed` keeps its uuid (sync upserts on it), so
the `escalations` unique and the claim's stale-`claimed`-only condition
already prevent a second alert — `escalation_test.sql` §٢ب proves it.

**Snooze is not a confirmation, so it does not clear the ladder — but it
removes the rungs it overtakes.** «فكّرني بعدين» at 8:10 means "leave me
until 8:25"; a rung at 8:15 would nag against that request, so rungs at or
before the snooze time are cancelled and rungs after it stay. Rule 5 is
untouched: «أخدته» / «مش هاخده» cancel everything for the slot at once.

**The server's grace is longer than the device's, and the gap is the sync
budget** (round 4.2b). `graceWindow` is 45 on the device;
`serverGraceWindow` is 60; `syncSlack` is the 15 between them, and the
invariant `serverGraceWindow == graceWindow + syncSlack` is locked by a
test. It is an **identity, not an inequality** — `syncSlack` is defined as
the gap, so 45 + 15 = 60 exactly; this file said `>` until round 4.2b part
2, and the test that "locked" it subtracted a minute to make `>` pass on an
`=`, which let any one of the three move alone. Both constants live in `domain/escalation/` so the SQL and the
device read the same numbers. **Why they must differ:** the father
confirms at +44, the push debounce is 3s, the cron ticks at +45 — the row
is still `pending` in the cloud and the son is alarmed about a pill taken
thirty seconds ago. That is not an edge case, it is the last minute of
every grace window, and it is the same false alarm 4.2a exists to
prevent. The device's own decision stays at 45, so «يومك» still says
«نسيتها؟» on time; the extra fifteen minutes buys the wire, not the
patient.

**The cloud must know a dose before its time** (round 4.2b, part 1).
The server escalates from rows that already exist, and it never resolves
anchors (3.5) — it reads the instants the father's device computed. A
father who ignores every notification wakes nothing, so `rescheduleAll`
materialises **yesterday, today and tomorrow**: yesterday because a
bedtime dose lands after midnight, today because a day the app never
opened still needs rows, and tomorrow so an ignored dose already has its
row in the cloud when its time comes. Materialising stays idempotent —
the key is (schedule, routine day) and `materializeDay` only adds what is
missing — so re-opening never duplicates a row. `test/data/sync/` proves
the chain: one morning open, no further touch, every dose of that day and
the next present in the cloud as `pending` before it is due. Build this
before any alerting code, and never after: with the rows missing the scan
finds nothing, yet every hand-run test still passes, because touching the
app is itself what creates the row.

**Not yet (4.2 / 4.3):** a real device token — `lib/data/push/` is built
and unit-tested but has never run on hardware, so every alert still
resolves to `no_token`; the son's alert screen (mockup 27), so a tap on
the alert opens «يومك»; Critical Alerts entitlement; the +90
«الدائرة كلها» rung. The cloud half is done and running: `0006`–`0009`
are applied to the live project and the scan ticks every five minutes.

**The server's decision is visible on the son's screen** (round 4.2c).
`CaregiverRemote.snapshot()` also reads `escalations` of the last 48
hours (`alertWindow`), and each one is a card at the top of
`CaregiverScreen`: «⚠ والدك ما أكّدش جرعة {med} الساعة {time}» plus one
line per `delivery_status`. Three decisions live there:
- **`no_token` is not a failure and is not worded as one.** The server
  decided and recorded, and the card the son is reading *is* the alert;
  only the device channel is not activated yet. So it says «تنبيه داخل
  التطبيق — إشعار الجهاز محتاج تفعيل», `sent` says «السيرفر بلّغك {sent_at}»
  and only `failed` says «الإشعار ما وصلش» — that one really did fail. A
  row still `claimed` is hidden: the send is in flight, and `0009` will
  settle or retry it within five minutes.
- **A dose taken later keeps its card** and adds «أكّدها بعدين ✓» — the
  alert happened; the outcome is the update, not a deletion (rule 5).
  `skipped` gets no ✓; he did not take it. Open cards are gold and always
  render above resolved ones even when the resolved alert is newer;
  resolved cards drop to ivory with a muted header — same sizes, because
  the header is body text at the 20px floor and fading it below the
  assumed contrast would be the same violation by another route.
- **Filtered to `caregiver_id = me` for wording, not access.** RLS lets a
  brother read alerts sent to his siblings (decided in 4.2b part 2), and
  «بلّغك» must not point at the wrong person. RLS is still the only
  scoping of what the circle may see.
No empty-state card, no sound, no animation; refresh is the existing
open/foreground/pull path (plus the visible-tab poll). `alertFromRow` is pure so the nested embed
(`dose_events → dose_schedules → medications`) is unit-tested without
Supabase — but the `!inner` embed filter on `patient_uuid` has **never
run against the live project**; if a card fails to appear on a device it
is the first suspect, and dropping that `.eq` is safe for a son with one
linked father.

**The son's side never resolves anchors** (round 3.5). Resolving needs
the father's routine plus the engine — a second scheduler that can silently
disagree with the real one. The father's device is the only scheduler; the
caregiver view (`lib/features/care/`, data via `CaregiverRemote` in
`lib/data/care/`) renders only what his device wrote onto `dose_events`
(`scheduled_at` instants), or shows nothing. Enforced by
`test/features/care/no_scheduling_imports_test.dart`. The screen reports,
it does not judge: a past-due unconfirmed dose is «لسه ما اتأكدتش» in gold —
never «فاتت», never red ("missed" is Phase 4's grace-window decision). The
footer is «آخر تحديث من موبايل والدك» from the max server `updated_at` —
deliberately not "last seen"; data changing proves nothing about the phone
being alive. The linked patient is identified via the caregiver's own
`care_relationships` rows, never by filtering `owner_id` client-side —
RLS is the only scoping. When a son follows more than one parent,
`linkedPatient` orders by `created_at desc` and takes one — without a
deterministic order Postgres may return the title from one parent and the
medicines from another, and the screen looks empty with no error.
**Refresh: open, foreground, pull, plus a 10-second poll (`refreshEvery`)
that runs only while the «متابعة» tab is visible and the app is in the
foreground.** The rule used to be «no realtime, no timers», and it left the
son looking at a frozen screen: the father confirmed, his phone had already
pushed, and the son's view stayed stale until he killed and reopened the
app. `CaregiverShell` keeps both tabs alive in an `IndexedStack`, so the
poll is gated by `CaregiverScreen.active` (`_tab == 0`) and cancelled on
`paused`/`inactive`; it restarts — with an immediate refresh — on resume or
on returning to the tab. `caregiver_poll_test` proves it stays silent on
«الإعدادات» and in the background, and fires on the tab (mutation-checked
both ways). No realtime yet: a Supabase Realtime subscription is the
intended **replacement** for the poll, not an addition to it. Offline keeps
the last snapshot visible under the agreed sentence.

**The cloud schema's only wall is RLS** (`supabase/` — SQL only, run by
hand in the SQL editor, order: 0001 → 0005 → tests). The publishable key
ships in the binary, so every table has RLS enabled as its first statement
and `anon` is stripped of table privileges entirely. Access checks for
*other* tables route through SECURITY DEFINER functions in `private` —
patients' visibility depends on care_relationships and vice versa, and
direct policies would recurse ("infinite recursion detected in policy").
Always `(select auth.uid())`, never bare. Cloud PKs are the device-minted
uuids; local int ids have no cloud column. Caregivers are read-only until
escalation adds one narrow UPDATE policy. After ANY schema change run
`tests/rls_test.sql` and the zero-rows `rowsecurity=false` check in
`supabase/README.md`.

**A table's policy must NEVER call a function that queries that same
table.** The row's own columns are already in scope inside the policy —
compare against them directly (`owner_id = (select auth.uid())`). The
definer-function indirection exists for one job only: reaching *other*
tables without recursion. Breaking this does not fail loudly at
`create policy` time; it fails on `INSERT ... RETURNING`, because
Postgres applies the SELECT policy to the new row inside the same
statement, where a subquery cannot yet see it. `patients_select` called
`can_access_patient(uuid)`, which queries `public.patients` — so every
new patient insert failed with 42501, always, for everyone. Fixed in
`0005_fix_patients_select.sql`, and `tests/rls_test.sql` now inserts a
patient, a medication and a dose_event **with RETURNING**, the way the
app does.

**Escalation rows are readable by the whole care circle, not just their
recipient** (round 4.2b part 2). `escalations_select` goes through
`private.can_access_patient`, so an accepted caregiver sees every alert
sent about that patient — including ones sent to his *siblings*, not only
to himself. For a family sharing one father that is the intended reading,
and it is why the policy is not `caregiver_id = (select auth.uid())`.
The same choice has a second consequence: a **revoked** caregiver loses
sight of alerts he previously received, because access is re-derived from
the relationship every time rather than stored on the row. Both of these
are visible behaviour, decided, not accidents.

`device_tokens` is the deliberate exception to the whole pattern: no
`can_access_patient` appears anywhere in it, in either direction. A linked
son sees his father's doses; he never sees his father's phone token, and
his father never sees his. Every policy on it compares `user_id` against
`(select auth.uid())` — a column already in the row, the cheapest possible
form of the rule above. Writes go through `public.claim_device_token`,
whose threat model is written out in `0006_push.sql` and tied to debt 2.

**`private` is not exposed to PostgREST, so the Edge Function reaches the
scan through one narrow `public` wrapper.** `public.due_escalations_for_service`
(`0007_escalate_rpc.sql`) has no body of its own — it calls
`private.due_escalations` and nothing else — and its EXECUTE is granted to
`service_role` alone, revoked from `anon` and `authenticated`. The two
rejected alternatives are worth naming: exposing the `private` schema in
API settings would publish every definer access function at once, and a
TypeScript copy of the scan inside the function is the "two definitions of
selection" this whole round exists to prevent. `escalation_test.sql`
asserts the wrapper and the inner function return the same rows, because
the wrapper is the one the Edge Function actually calls.

**An interrupted send retries after 5 minutes, and the duplicate that can
cause is chosen deliberately** (`0009_escalation_retry.sql`). The function
claims a row, then sends, then writes the result; if it dies in between —
timeout, recycle, redeploy — the row sits at `'claimed'` forever and
`due_escalations` used to exclude it, so that dose would never alert
again, silently. Now a row still `'claimed'` after
`private.escalation_retry_after()` (5 minutes) becomes due again, and the
claim is a single atomic statement
(`public.claim_escalation_for_service`) that inserts or takes over a dead
claim — **not** an INSERT whose 409 the function reads as "already
alerted", which is what made the plain SQL fix a no-op until the Edge
Function changed with it.

**The threshold must exceed the function's maximum lifetime.** Shorter,
and a slow-but-still-running send gets a second claim from the next tick,
manufacturing in the normal case the duplicate that should only ever
happen during a failure. Never trim it for a faster retry; the number is
about being sure the holder is dead, not about speed.

**And the judgment, because it is the whole basis of the fix:** if the
function died after FCM accepted the message but before writing `'sent'`,
the retry sends the alert twice. A son annoyed by a duplicate has a second
of confusion and then checks on his father. A son **never told** his
father missed a dose is the failure this entire product exists to prevent,
and with phone calls cancelled this push is the last rung. We choose the
duplicate. (This is unrelated to rule 5's ban on a recall: there we would
spend a channel that must stay meaningful to unsay something; here we say
the same true thing twice.) `'sent'`, `'no_token'` and `'failed'` are
written decisions and stay excluded forever.

**The cron reads the service role key at run time, not at schedule time**
(`0008_escalation_cron.sql`). Interpolating it into the scheduled command
would store it verbatim in `cron.job.command`, readable by anyone who can
read that table. So the job is literally `select
private.run_escalation_scan()`, and that function looks both the URL and
the key up in Vault on every tick. Missing secrets raise a loud exception
every five minutes into `cron.job_run_details` — correct noise: it means
the last rung of the ladder is down. `pg_net` does not wait for the
response; it queues the request and a background worker runs it, so the
reply lands in `net._http_response`, which is the first place to look when
an alert does not arrive. Two overlapping runs are harmless — the unique
on `escalations` is what prevents a double alert, never the cron's timing.

**The caregiver channel id is a second cross-language mirror.**
`fakkarni_caregiver` is written in Dart
(`NotificationService.caregiverChannelId`) and in TypeScript
(`CAREGIVER_CHANNEL` in the Edge Function). If they drift, Android drops
the alert onto the default channel — **no error anywhere** — so the last
rung arrives at ordinary priority, or not at all if the son muted that
channel. `test/data/push/push_channel_test.dart` reads the function file
and fails if either side moves, exactly like the grace-window mirror.

**The selection query has exactly one definition, in SQL.**
`private.due_escalations` is called by the cron, by the Edge Function and
by `tests/escalation_test.sql`. A copy of the scan written in TypeScript
would let the test prove a statement the function never runs — which is
precisely how `rls_test.sql` passed over the `0005` bug. Anything that
picks rows for alerting lives in that function or it does not exist.
`private.server_grace_window()` is the only place `60` appears in the SQL,
and `due_escalations` is forced through it — the number is a **mirror** of
`serverGraceWindow` in `domain/escalation/`, and the mirror is held by
`test/data/sync/server_grace_sql_test.dart`, which fails if either side
moves alone. Postgres cannot read Dart; drift between the two shows up as
a false alarm on a son's phone, never as a failing build, so the test is
the only thing standing there.

**If a migration file changes after you have run it, say so — out loud, in
the next message, with "re-run it".** "I ran `0006`" and "the file now on
disk has run" are different facts, and the gap between them is invisible
from both sides: the file looks right to whoever reads it, and the database
looks right to whoever ran it. A function that was never actually created
costs half an hour of debugging something that is not broken. This applies
to a comment-only edit too — the cost of saying so is one sentence, and
nobody can tell from the outside which kind of edit it was.

**SQL migrations are run against the real project in the same round that
writes them, before that round is committed.** Both of the above shipped
green because the SQL had never been executed — `0004` collided on a
`day_routines.updated_at` that `0001` already created, and the policy bug
above was invisible to a test that inserted without RETURNING. Code
nobody has executed is not code, however carefully reviewed. Every
migration must be idempotent (`if not exists`, `create or replace`,
`drop ... if exists` before `create`) so re-running the whole chain is
always safe. That promise was **false** until round 4.2b part 2: `0001`
died on its first `create table` and `0002`/`0003` on their first
`create policy` against any live project, while the README said the chain
replayed. A README that lies costs a morning. The known price of
`if not exists` is that a replay never reshapes an existing table — which
is correct: migrations are history, and a shape change gets its own
numbered file, never an edit to an old one.
And when a test passes over a bug, fix the test's *shape* — ours exercised
a different statement than the app, which is not thoroughness but a blind
spot.

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

0. **Cloud coverage is two days, and the son can see when it runs out.**
   Each app open uploads today and tomorrow, so escalation keeps working
   for about two days with no interaction at all; after that the cloud
   goes stale and the server has nothing current to judge. This is not
   filed as an invisible risk — the caregiver footer
   («آخر تحديث من موبايل والدك») turns **gold** once the last update is
   older than `staleAfter` (24h), before coverage runs out rather than
   after, and adds «اطمن عليه». Gold means "this needs your attention
   now", and a father whose phone has said nothing for a day is exactly
   that. Do not bury this under a retry or a background fetch; the
   silence is the signal.
0b. **A confirmation made offline can still alert the son.** He takes the
   pill, confirms, and the push cannot leave — the cloud row stays
   `pending` past +60 and the son is told. `syncSlack` covers a slow
   wire, not a dead one. Inherent to any server-side scan; his view
   corrects on the next refresh (rule 5).
1. **Sync has no deletes and no second owner device — yet.** Deletes ship
   as soft-delete (`deleted_at`) with the first feature that needs one;
   a second device for the same owner ships as last-write-wins by
   `updated_at`. Neither exists today, and nothing may pretend to handle
   them until they do. A dose confirmed from the lock screen stays dirty
   until the next app open/foreground (the background isolate builds no
   SyncService).
2. **Anonymous sign-in is a development stand-in ONLY.** An anonymous user
   is bound to one device and is lost when app data is cleared. It must be
   upgraded via `linkIdentity` to Google before any store submission.
   **Shipping with anonymous auth is forbidden.**
   **It also costs us `public.claim_device_token`.** Anonymous sign-out
   mints a *new user on the same device*, so the unchanged FCM token
   collides with a dead user's row; the function reattaches it atomically
   and trusts possession of the token as proof. The accepted risk is named
   in `0006_push.sql`: whoever obtains another install's token can claim
   it, and that victim's phone then receives alerts naming a stranger's
   patient and medication. Low risk today — the token leaves neither the
   device nor our server. **When this debt is paid the collision disappears
   at its source** (a real Google/Apple id survives sign-out), so delete
   the function and go back to a plain upsert under RLS. Revisit it here,
   not somewhere it will be forgotten.
3. **Sign in with Apple is mandatory before any iOS App Store submission**
   once Google is offered (Guideline 4.8). Blocked until the paid Apple
   Developer account exists. It lands as a sibling `AuthService` file.
4. **Huawei / no-GMS devices cannot use Google Sign-In** — a real segment
   in Egypt. May require adding an email provider later; `AuthService`
   must stay open to it (which is why the interface is provider-neutral).
**Deferred by decision (not by oversight):**
- **Mockup 21's «الروشتة لو مش مكتوب فيها ميعاد؟» policy block is not
  built.** Its third option («افترض من غير ما تسأل») lets an AI reading
  become a scheduled dose without a tap — rule 4 forbids exactly that.
- **`accountType` is not stored.** «Roles emerge from data… there is no
  role column» (3.3). Mockup 2's cards are the D4 entry screen — it only
  routes; the choice lives in memory and is gone once setup ends (see D4).
- **Google and Apple sign-in are shown disabled on mockup 3, each with its
  own real reason** — Google «قريباً», Apple «محتاج حساب Apple Developer».
  They are not buttons (no InkWell, a lock, a muted fill), a test taps them
  and asserts zero sign-in calls. The only working control is «كمّل بحساب
  تجريبي», labelled as what it is (debt 2). Email is not offered (Email OTP
  was removed from the product).
- **Mockup 33's rows with no backend are not built:** نمط كبار السن,
  التنبيهات, الاسم والسن, بطاقة الطوارئ, تصدير البيانات. A settings row that
  opens onto nothing is worse than a row that is not there. Each returns
  with the feature behind it. «اللغة: عربي» is shown disabled — no English
  in this version, and the row says so instead of pretending.
- **Mockup 09's voice-add button is not built** — no speech input exists.
  Adding goes through the shell's «ضيف».
- **Mockup 15's per-member permissions (checkboxes per caregiver) are not
  built.** There is no permissions table in the backend; a permissions UI
  that changes nothing is worse than none. Ships with the schema that
  makes it true, or not at all.
- **The invite *link* (`fakrny.app/join/…`) is not built.** The 6-digit
  code is live and verified on the cloud; a link needs a domain and a deep
  link that do not exist. The design's invite block is used with the code
  inside it; «ابعته» copies the ready message (no `share_plus` before the
  demo — the callback is injectable when it lands).
- **Mockup 22's «قواعد الافتراض» block (قبل/مع/بعد الأكل + gap stepper +
  live 1×/2×/3× table + default duration) is not built — and not because
  of time.** «مع الأكل» and «المدة» are now asked **per medication** in the
  «ضيف دوا» path, which is more precise than one global rule; a global
  rule would be a second place holding the same decision, free to
  disagree with the first. If it ever returns it must *feed* the per-dose
  defaults, never override them.
- **Mockup 10's voice line («قول تمام لتسجيل الجرعة») is dropped, not
  deferred.** The app has no TTS and no speech input. A line asking a
  72-year-old to speak to a phone that cannot hear him is worse than no
  line: he says «تمام», nothing happens, and the dose he just took looks
  unconfirmed. If voice confirmation is ever built, it lands as a real
  input path with its own test, and only then does the line come back.
- **Escalation rung 5 («+٩٠ — دائرة الرعاية كلها») is not built**, so the
  alert screen's ladder shows the four rungs that exist and its ramp stops
  at `F.orange`. Red never appears on it — the fifth rung would have been
  the only red, and drawing it would promise an alert nobody sends.
- **«لا أذكر» on the alert screen** — no state for it in `dose_events`;
  «تخطّي» with a human asking covers the same case.
- **Mockup 18's «📞 اتصل بمحمد» (and its «اتصل» tab) is not built.** Since
  D3.4 the patient can type emergency contacts (name, number, relation),
  stored **on this device only** and never synced — so the old reason ("we
  collect no phone numbers") no longer holds. The honest reason now: a call
  button on the elder home lands *on top of* those contacts (which one is
  «ابنك»?), not on its own, and the one-tap «طوارئ» card already carries
  their call buttons. The server still holds no phone number, and phone
  calls from the escalation ladder stay cancelled. Elder mode's
  second tab is «الإعدادات» instead: it is the only way back out of the
  mode. Its voice line («قول تمام وأنا هسجّلها») is dropped for the same
  reason as mockup 10's.
- **Mockup 32's emergency card on the real lock screen is not built.** That
  needs a WidgetKit extension in Swift plus an App Group for the data, and
  the Android equivalent. What exists is an **in-app full screen** with the
  same look and function, one tap from the top bar in every tab (and in
  elder mode). No user-facing text calls it a lock-screen card or says it
  works «من غير فك الموبايل»; a test asserts that.
- **Mockup 19's «ملاحظة للمسعف» field and mockup 32's «مشاركة سريعة» are
  not built** — not in the plan, and sharing needs `share_plus`.
- **Mockup 13's «استخراج الملف» waits for
  D3.8, and its «نشطة/منتهية» chips and 29's «إيقاف دوا» entries come from
  `medications`, not records, so they are not on these screens.
- **A manual «روشتة» or «حجز» record schedules nothing.** Both forms say so
  in words; medicines are added through «ضيف», and bookings have no
  notification band.
- **Mockup 14's voice entry is not built** — there is no speech input.
  Glucose is typed. Its «المستهدف» line and «أعلى من المستهدف» chip are
  not built either: that is a textbook target dressed as an interface.
- **Mockup 7's multi-page capture is not built** — one page per scan.
- **Mockup 8's lab reference range, «أعلى» chips and red cards are not
  built, and cannot be:** the Gemini schema has no field for a range, a
  flag or an interpretation, so none can reach the screen.
- **Mockup 11's rule box («قاعدة: لا يمكن للفحص أن يبقى…») and «المتوقع ٢٤
  ساعة» are not built** — an automatic judgment on delay and a number
  nobody gave us. The fasting duration is never ours either: the user types
  the hours the lab gave.
- **The calendar shows doses only where `dose_events` rows exist** (up to
  tomorrow). It does not recompute future days with the engine, and says so.
- **The son adding visit questions from his own phone is not built** — it
  needs the cloud; questions are written on the patient's phone only.
- **Mockup 16's trend arrow («↑ عن الشهر السابق»), the red lab arrows and
  the medication stop reason are not built** — a judgment, a colour we do
  not spend, and a field nobody stores.
- **Mockup 30's second per-section control is not built:** a switch and «👁
  مرئي» meant the same thing; there is one 👁 «هيظهر» / 🙈 «مخفي» chip.
- **Mockup 17's star ratings are not built, and never will be from OSM.**
  OpenStreetMap has no ratings; a made-up star on a real pharmacy is a lie
  told to people, not a UI detail. «Concor 5mg متوفر», «توصيل ٤٥ د» and
  «بيقبل تأمينك» are not built either — no source holds them. Its «معامل»
  filter is left out (not in the brief).
- **Mockup 26's «ساعات الهدوء» is not built.** README's rule is that quiet
  hours silence everything **except** a missed dose and emergency — and
  those are the only alerts we have, so the switch would do nothing. A
  settings row that does nothing is worse than a row that is not there.
- **Mockup 26's other rows wait for their features:** «نداء الطوارئ 🔒»
  lands with D3.4 (a locked row would promise an alert nobody sends),
  «قراءة سكر غير معتادة» with D3.6, and «عضو أكّد جرعة» / «انضمام عضو
  بالرابط» / «رفع تقرير أو تحليل» when a notification exists behind them.

4b. **«قريب منك» runs on public OpenStreetMap services — fine for a demo,
   not for a store launch at scale.** Overpass's policy says an app for
   regular users on the public instance "requires your own instance"
   (~10k requests/day guideline); the tile policy allows small apps
   (distinct User-Agent, attribution, ≥7-day caching, no offline bulk) but
   access "may be withdrawn at any point". Before launch: our own Overpass
   instance or a paid provider, and a tile provider that allows commercial
   use. Doctors' coverage in Egypt on OSM is thin and is shown as-is.

4c. **Every install still gets an empty «أنا» patient row at boot** (D4
   took option A2). `buildServices` calls `ensurePatient()` and
   `AppServices.patientId` is a non-null int that the scheduler, every
   screen and the lock-screen isolate rely on — so "has a patient" is
   *derived*: a saved routine **or** a non-null `sex`
   (`RoutineRepository.watchHasPatient`). The son's phone therefore holds a
   row that is not a patient; `SyncService` never pushes a patient with no
   routine and no medications, so it cannot reach the cloud and make him
   one. **The correct long-term shape is A1:** create the row only when
   «نتعرّف عليك» saves, and build the patient-bound services after that.
   It is a refactor of everything that reads `patientId`, not a tweak.
5. **`F.muted` (`#6E7F76`) on ivory is ≈ 4:1 — it fails WCAG AA for
   normal text at 17px** (AA needs 4.5:1). README's token table was
   followed as-is for the demo (design fidelity «high»). For a
   72-year-old with reading glasses this is the wrong side of the line.
   The fix is one line: secondary *text* uses `F.mutedDark` (`#43544C`,
   ≈ 7:1) and `F.muted` stays for icons and dividers. Do it before any
   real patient uses the app, not after a complaint.

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
  reader. Threshold 0.8; below it the medicine's row gets a gold side edge
  and «مش متأكد من دي — راجعها», listing each unsure field with its note.
- Scan screen (D2.3, mockup 05): corner frame over the captured photo,
  «صوّر الروشتة» 64px with «اختار من الصور» / «أكتبها بإيدي» 56px under it.
  **The line-by-line reveal is honest by construction:** Gemini returns
  everything at once, so while waiting the frame shows only «بيقرا
  الروشتة…» with a pulsing dot and **no marked lines**; once the reply
  lands the reveal walks the lines that actually came back (their real
  count and names — dashed until read, filled ivory after), then goes to
  review. Boxes are stacked, not placed: the model returns no coordinates
  and drawing on an imagined spot would be the same lie. Pinned by a test
  that completes the reader mid-flight. Then the review screen (D2.2, mockup 06): one
  row per medicine — mono name, resolved time shown in Arabic digits (never
  stored), a chip with the rule not the time, «عدّل» with icon + word — a
  dashed «أضف دوا ما اتعرفش عليه» row, and «أعدّل» / «تمام، ظبّطهم» as two
  solid dark buttons of identical size and type (the test compares style,
  not just size), plus «صوّر تاني» — which returns
  to the scan screen so both sources are offered again, never auto-opening
  the camera.
  «تمام، ظبّطهم» writes each clear line (one schedule per timing) then `rescheduleAll`.
- Editor accepts prefilled values and now has an optional amount field;
  the offset stepper follows the chip (30 before meals, 15 before sleep).
  Since D2.5 the timing lives in one shared `DoseEditor`; «ضيف دوا» asks
  name / amount / «كام مرة» / «مع الأكل» / duration first and hands off to
  it once per timing («الجرعة ١ من ٣»), saving nothing until the last
  «احفظ الجرعة». «كام مرة» → meals is our operational convention (١×
  الفطار، ٢× + العشا، ٣× + الغدا), every page editable. The design's
  `{ anchor: … }` line is a designer's note, not UI — not built.
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

**Round 4.1 — the local ladder on the father's phone (built, not yet
device-verified)**
- `domain/escalation/escalation_ladder.dart` (pure) + tests; bands 10M and
  30M; `planEscalations`, `isRescheduledId`, `snoozePendingSlack`;
  ladder planned from now − 45; rule-5 cancel covers both rungs; snooze
  clears overtaken rungs only; `sweepMissed` + yesterday/today
  materialisation inside `rescheduleAll`; resume hook reschedules;
  `fakkarni_escalation` Android channel; «نسيتها؟» / «اتنست» on «يومك»,
  `missed` verbatim on the caregiver screen. No schema change.
- Device check pending: dose two minutes out, phone locked → rings +0,
  +15 (vibrates), +30; repeat and tap «أخدته» at +16 → +30 never rings;
  untouched past +45 → «يومك» shows «نسيتها؟».

**D3.1 — the front door (built)**
- Schema v8: `patients.sex` (`Sex.m`/`Sex.f`) and `patients.age`, both
  nullable and **local** (sync still sends uuid/name/slot only). Written
  red first: the SchemaVerifier failed with «no such column: sex», then the
  step went in — and moving the normalization to the end of the chain was
  what made v2→v8 and v5→v8 pass.
- «نتعرّف عليك» (mockup 21) before «ظبّط يومك» when `sex` is null: name,
  راجل/ست, optional age (range chip then stepper; untouched = null — no
  invented age). Existing installs are not re-asked.
- **Sex-keyed copy layer:** `domain/patient/sex.dart` → `Say`, provided by
  `PatientVoice` / `PatientVoiceScope` above the Navigator. Applied to the
  sentences that address the patient in onboarding («بتفطر/بتفطري»,
  «مش متأكد/ة»), the alert («خدته/خدتيه خلاص», «ارجع/ي ليومك», «أخدته/ي
  {time}») and the rail («نسيتها/نسيتيها؟», the ✓ line, «خلصت/خلّصتي»).
  Unknown sex (pre-v8) = masculine, exactly the text it had. **Buttons in
  the patient's own voice stay as they are** — «أخدته» on the pinned card is
  the patient saying "I took it", identical for both. Everything else moves
  over screen by screen.
- Mockup 3 restyled on `SignInScreen` (see deferred list for the honest
  Google/Apple rows); mockup 2's cards for the post-sign-in path choice.

**D3.2 — the home (built)**
- The home (mockup 04) sits **at the top of the «اليوم» tab** and replaces
  the pinned next-dose card; «جدول النهاردة» stays below it. Tabs unchanged.
  Why: a separate home tab would show the same next dose twice, with two
  places to confirm it.
- Order: «يومك» + «صباح/مساء الخير يا {name}» + «{name} · {age} سنة» (only
  when an age exists) + `say.whatNow` («تعمل/تعملي إيه دلوقتي؟» — the
  mockup's «ماذا أفعل الآن؟» is MSA). Then «الآن», «خلال ٤٨ ساعة»
  (tomorrow's doses), water, the rail.
- «الآن» (`NowCard`): unconfirmed past doses (oldest first), then the next
  one. **All gold, neutral wording** («لسه ما اتأكدتش · كان معادها …») —
  the mockup's red cards are not ours. Only the first card has the primary
  «تأكيد الجرعة/الجرعات»; the rest have «افتح» (ReminderScreen).
  «لاحقًا» is the real 15-minute `scheduler.snooze`, and the card says so.
  «مش هاخده» now lives only on ReminderScreen.
- Water (`WaterWidget`): cups 0–8, interval 1/2/3 h, countdown ring. Three
  `shared_preferences` keys (`water.*`), local, not synced, reset on a new
  calendar day. No notification, no advice — 8 is the counter's limit, not
  a recommendation. The one periodic timer runs only after the first cup
  and is cancelled in `dispose` (mutation-checked: removing the cancel
  fails the test).
- **No sugar or lab cards until D3.6** — they get added to «الآن» then.

**D3.3 — elder mode + notifications (built)**
- Schema v9 `device_preferences`: one local row (`id = 1`, not synced) —
  `elder_mode`, `rung_first_on`, `rung_second_on`; no row = defaults.
  Written red first (the SchemaVerifier failed with «does not contain
  device_preferences»), frozen SQL above the `from < 6` block, and the v2
  file test now checks the table is empty. In drift, not
  shared_preferences, because the lock-screen isolate reschedules too.
- **The rung switches filter, they do not change the ladder.**
  `ReminderScheduler.preferences` is read at scheduling time only; rungs
  from `planEscalations` whose `escalationRungOf(id)` is off are dropped
  before `reconcile`, so an already-pending one is cancelled as stale.
  `planEscalations`, `ladderFor` and the domain are untouched.
  `buildServices` (app **and** background isolate) passes it — a test
  guards that line. Mutation-checked: dropping the filter fails four tests.
- «التنبيهات» (mockup 26): «تفويت جرعة», «في الموعد» and «+٦٠ د — إشعار
  لابنك» are 🔒 «دائمًا» with no switch at all; only +١٥ and +٣٠ switch,
  and each change reschedules at once. Banner in colloquial
  («الإعدادات دي على الموبايل ده بس»).
- **The son's rung reads +٦٠ everywhere now**, from `serverGraceWindow`
  — the reminder screen said «+٤٥» (the device's grace), which promised
  an alert before the server sends one.
- «نمط كبار السن» (mockup 18): a switch in settings (gold when on). When on,
  `AppShell` shows two tabs («الرئيسية», «الإعدادات») and no «ضيف»;
  `ElderHomeScreen` shows the greeting and **one** dose card — the first of
  `nowGroups`, the same selection as the home — with «تم ✅» (green, 80)
  and «بعد شوية ⏰» (real snooze, 64). Sizes come from `F.elder*` and are
  **above** the normal floor (text 24+). Confirm and snooze are the shared
  `confirmGroup` / `snoozeGroup` in `features/today/dose_actions.dart`,
  used by the home too. The settings tab keeps normal sizes.

**D3.4 — emergency (built)**
- Schema v10 `emergency_profile`: SyncIdentity columns and a touch trigger
  from day one (PHASE_D3 rule 2), one row per patient: `blood_type`,
  `allergies`, `chronic_conditions`, `contacts_json` (`[{name, phone,
  relation}]`). Written red first; frozen SQL above the `from < 6` block.
  **Not synced**: SyncService never reads it, and
  `test/data/sync/emergency_not_synced_test.dart` fails if that changes
  silently. Current medications are read from `medications`, never copied.
- **No field is ever filled or guessed.** null renders «لسه ما اتملاش», and
  nothing else — no «لا يوجد», no default blood type. Blank input saves
  as null; «مفيش حساسية» has to be typed by a person. A blood type outside
  the eight is refused, not stored. The only writer is
  `EmergencyEditScreen` (8 chips + «مش عارف» = null, free text, contacts).
- «معلومات الطوارئ» (19) on `F.redDeep`, «بطاقة الطوارئ» (32) as a full
  in-app screen with the gradient and a live clock (timer cancelled in
  dispose). Every contact has an «اتصال» button; the ambulance button
  pulses (short pulse on a timer, off under reduced motion) and **always
  asks «تتصل بالإسعاف ١٢٣؟» first** — mutation-checked: dialling directly
  fails the test. Entry: ink «طوارئ» in the top bar → card (all tabs,
  elder mode); settings «معلومات الطوارئ» → screen 19.
- `url_launcher` for `tel:` (`dialNumber` is swappable for tests); `tel` in
  `LSApplicationQueriesSchemes`. Contact calls go straight to the OS: iOS
  asks "Call …?" itself, Android opens the dialer without calling. Not yet
  tried on hardware — the simulator cannot place a call.

**D3.5 — records (built)**
- Schema v11 `records` (local, SyncIdentity columns + trigger, not synced —
  `test/data/sync/records_not_synced_test.dart`): kind (imaging | visit |
  lab | prescription | booking), title, happened_at, doctor, **place** (added
  beyond PHASE_D3's list: the imaging centre, lab and clinic fields of
  mockup 28 had no column), notes, attachment_path, deleted_at. Written red
  first; frozen SQL above the `from < 6` block.
- **Soft delete is a promise, and the promise runs.** `deletedAt` is set,
  the row stays in place on «الملف الصحي» and «الحالات السابقة» — struck
  through at 45%, with «اتمسح», «هيتمسح نهائي بعد ٣٠ يوم — تقدر ترجّعه لحد
  كده» and «↺ رجّعه» at full contrast. There is no trash screen and the
  text never mentions one (the brief's «يُنقل إلى المحذوفات» was MSA and
  untrue). `launchHousekeeping` in `main.dart` calls
  `RecordsRepository.purgeDeleted` on every launch: rows deleted more than
  `retentionDays` (30, the number the text is built from) ago are removed
  for good; 31 days goes, 29 stays, both under test.
- «إدخال يدوي» (28): five forms, same primitives, own labels per kind;
  date chips («النهارده»/«امبارح», «بكرة» for a booking) + a date picker.
  «الملف الصحي» (13): search across title, doctor, place, notes and the
  written date in Arabic or Western digits; «⋯ خيارات» (a word, not a bare
  icon) → «امسحه» → confirm. «الحالات السابقة» (29): timeline newest first,
  kind and period filters (period uses calendar arithmetic). Every empty
  state says «لسه مفيش حاجة هنا» and how to add. Entry: settings «الملف
  الصحي», and a third option in the «ضيف» sheet.
- **The review screen fills the file from real use.** «تمام، ظبّطهم» writes
  one `prescription` record (date, medicine names; the doctor only if the
  reading is confident — otherwise null). It runs after the medicines and
  `rescheduleAll`, wrapped and logged: a failed record never undoes a
  confirmation. «صوّر تاني» writes nothing.

**D3.6 — glucose + labs (built)**
- Schema v12 (written red first): `readings` — **blood glucose only**
  (`value_mg_dl`, `measured_at`, `context` صايم | بعد الأكل); no pressure,
  pulse or weight exist in this product. `lab_results` — one row per
  confirmed test (record_id → `records` lab row, test name as printed,
  value, unit). Both local with SyncIdentity columns + triggers, and the
  no-sync guard test covers them.
- **The dangerous screen follows two rules that do not bend.**
  (a) Number, range, difference — stop. No advice, no diagnosis, no
  «يُفضّل», no «راجع دكتورك», no «ممكن يكون». `GeminiLabReader.systemInstruction`
  says so explicitly (pinned by a test); the schema carries only test,
  value, unit, lab and date, so no model free text ever renders.
  `adviceWords` in `features/health/usual_words.dart` is checked against
  the rendered text of 14, 8 and the home card **and** against every
  string literal in `lib/features/health/` — mutation-checked: putting
  «مرتفع» in the comparison fails three tests.
  (b) «المعتاد» means **his** usual (`domain/health/usual_range.dart`,
  pure): lowest–highest of his last 10 values — glucose needs 5 in the
  same context, a lab test 2 earlier values in the same unit. Below that
  the screen says «لسه ما عندناش قياسات كفاية نعرف المعتاد ليك» and marks
  nothing. A different unit says «مش هنقارن». Never a reference range.
- «قياس السكر» (14): typed, 20–600 refused as a typo («برّه اللي أجهزة
  القياس بتقراه»), context must be chosen, latest reading + his usual +
  a plain green line. «تصوير تقرير تحليل» (7): the prescription transport
  (`GeminiPrescriptionReader.generate`) with another prompt, and the
  shared `ScanStage` — no line marked before the reply, reveal walks what
  came back (tested with a mid-flight completer). «قراءة التقرير» (8):
  unsure lines gold «مش متأكد من دي — راجعها» and block «تمام، احفظه»
  until edited or removed; «صوّر تاني» carries equal weight.
- Confirming saves a `lab` record + `lab_results` + the photo through
  `AttachmentStore` (relative path in `attachment_path`); the 30-day purge
  deletes the file after the row.
- Home: the glucose card is gold and sits in «الآن» **only** when the
  latest reading is outside his own usual; otherwise a quiet card above
  water. «افتح» is secondary. Entry: «ضيف» sheet («قيس السكر», «صوّر
  تقرير تحليل») and «الملف الصحي».

**D3.7 — calendar + checkup (built)**
- Schema v13 (written red first): `records.checkup_stage` (1..7, null = not
  a cycle — every earlier lab record) and `records.fasting_reminder_at`
  (the scheduled instant, null = none; the ID itself is derived, never
  stored). Columns added with an existence check above the `from < 6` block.
- «دورة الفحص» (11): seven stages from `domain/health/checkup.dart`; done ✓
  green, current numbered in gold (the state you are on), later faded. The
  user advances by hand. The subtitle stays, in colloquial: «الفحص مش ميعاد
  واحد — كل خطوة ليها وقتها، وهنا بتعرف وقفت فين». Started from «الملف
  الصحي» («ابدأ دورة فحص»); cancelling = the D3.5 soft delete.
- **«اضبط تذكير الصيام» schedules a real notification — only from that
  tap (rule 4)**, at draw time minus the hours **the user types** (no
  default, rule 6), through `NotificationService.scheduleCheckup`: its own
  Android channel `fakkarni_checkup`, **no «أخدته»/«فكّرني بعدين» buttons,
  no dose category, no payload** — those buttons record doses. It is
  cancelled by going back a stage, advancing past «سحب العينة», stopping
  the cycle, or deleting the record from «الملف الصحي» (all through
  `CheckupService`); restoring a deleted record does not reschedule it.
  A third concurrent reminder is refused with words.
- «التقويم» (12): month/week (week starts Saturday), filters دوا (incl.
  prescription records) · زيارة · تحليل · أشعة · حجز · سكر. Days with
  entries get neutral green dots; a gold edge only for an unconfirmed past
  dose. Tapping a day shows its entries below. Reads
  `DoseEventRepository.watchBetween`, records and readings — no new table.
  Entry: «التقويم» on «الملف الصحي». Day cells are 64 tall but ≈53 wide on
  a 402pt phone — seven columns do not fit 56 each; the whole cell is the
  target.

**D3.8 — doctor page + export (built)**
- Schema v14 `visit_questions` (body, created_at, asked; local,
  SyncIdentity + trigger, no-sync guard). Written red first.
- «ملخص زيارة الطبيب» (16): current medications with their rules, glucose
  for the last 30 days per context (count · lowest · highest · average),
  the latest value of each lab test with «كان X في {date}», the nearest
  booking, and family questions («اتسأل ✓»). **Numbers and facts only** —
  the D3.6 banned-words test now also reads this screen and every string
  literal in `features/doctor/` and `features/export/`, plus «يبدو»،
  «نستنتج»، «غالباً».
- «استخراج الملف» (30): period + one 👁/🙈 chip per section. **Hiding is
  enforced at generation:** `collectExport` never queries a hidden section,
  so it is not in the PDF at all. `test/features/export/export_pdf_test.dart`
  builds an uncompressed PDF, decodes its ToUnicode maps, and asserts a
  hidden section's Latin tokens are absent — after a positive control that
  finds every token with all sections visible (mutation-checked: ignoring
  the hidden flag fails three tests). Emergency is hidden by default;
  contact phone numbers never enter the file.
- «معاينة الملف» (31): the actual PDF bytes rasterized (`printing`), and
  those same bytes are what gets saved and shared (test asserts identity).
  «احفظ وشارك» saves to `Documents/exports/` (visible in Files via
  `UIFileSharingEnabled`), states that location, then opens the share
  sheet; if the sheet does not open the location stays on screen. «طباعة»
  opens the system print dialog.
- **Arabic in the PDF was verified by looking at a generated file, and it
  was broken first.** `pdf` shapes letters correctly but measures a word by
  its ink, not its advance, so words ending in a long-tailed letter ran into
  the next («سكرصايم»), and mixed Arabic/Latin lines came out reordered.
  `arabicLine` in `export_pdf.dart` fixes both: one `Text` per Arabic word
  padded with ink-less NBSPs (the box then follows the advance), Latin runs
  grouped into one LTR `Text`, all in an RTL `Wrap`; diacritics are stripped
  in the PDF only (a shadda landed off its letter). Re-check with a real
  render (`qlmanage -t`) after touching it — the code saying `rtl` proves
  nothing.
- Entry: «صفحة الطبيب» and «استخراج الملف» on «الملف الصحي». New
  dependencies: `pdf`, `printing` (no `share_plus`).

**D3.9 — nearby (built) — the 33rd screen**
- PHASE_D3 said this needed billed Google Places. It does not: verified
  with a live Overpass query around central Cairo (no key, no account)
  and a live OSM tile; both usage policies read and quoted in the
  corrected PHASE_D3 line and in debt 4b.
- `lib/data/places/places.dart`: one Overpass query per search (pharmacy +
  `amenity=doctors` + `healthcare=doctor` in 2 km), the location rounded
  to 3 decimals (~110 m) **before** it leaves the phone — and the screen
  says it leaves («بنبعت مكانك التقريبي لـOpenStreetMap»); app User-Agent;
  24-hour cache keyed by the rounded point (shared_preferences). Offline
  with a cache shows those results with their date; without one, a plain
  message. Re-search only from «دوّر من مكاني تاني», never on map drag.
- `domain/places/opening_hours.dart` (pure) answers «فاتحة/قافلة» **only
  when it understands the whole tag** (24/7, day ranges incl. wrap, several
  spans, overnight, off); anything else → no verdict, the tag is shown
  verbatim. A wrong «فاتحة» walks a 72-year-old to a closed door.
- `NearbyScreen`: OSM tiles via `flutter_map` (built-in cache honours
  Cache-Control/Expires; `userAgentPackageName` set), our own «© مساهمو
  OpenStreetMap» label on the map (flutter_map's widget doubled the © and
  reordered the Arabic), `KeyboardOptions.disabled()` (the map's autofocus
  scrolled the privacy line off screen). Cards: name (or «صيدلية من غير
  اسم على الخريطة»), distance, open state only as above, «اتصل» only with
  a phone tag, «الطريق» → Apple Maps / `geo:`. Both are secondary buttons —
  a primary per card would break the two-primaries rule.
- Location permission is requested when the screen opens and nowhere else
  (`geolocator`; `NSLocationWhenInUseUsageDescription`, Android coarse/fine);
  denied, denied-forever («افتح الإعدادات») and service-off each get words.
- Entry: «صيدليات ودكاترة قريب منك» on «الأدوية», and «قريب منك» in
  settings. New dependencies: `flutter_map`, `latlong2`, `geolocator`.

**Ramadan mode (built, screen restyled in D2.7)**
- `domain/scheduling/ramadan.dart` (pure): `RamadanTimes` (Cairo defaults
  18:00 / 03:30) and `ramadanRoutine(original, times)` — breakfast → Iftar,
  lunch → Iftar too (a «قبل الغدا» dose merges instead of vanishing),
  dinner → Suhoor, sleep = Suhoor + 60, wake unchanged.
- Schema v7 `routine_backups` (device-only, not synced): its row existing
  IS the toggle. `RoutineRepository.enterRamadan` writes the backup BEFORE
  the routine and updates `day_routines` in place (same uuid);
  `leaveRamadan` restores it verbatim. Re-entering while on recomputes
  from the stored original, never from the live routine. ON→OFF twice
  equals the start (tested).
- `features/routine/ramadan_screen.dart` (mockup 25): «يومك في رمضان»,
  state card (gold when on), Suhoor / Iftar editable with sleep derived,
  and the preview as the heart — «N أدوية هتتحرك» with before → after per
  medication from the real engine, fixed doses listed as unmoved. **One
  button that IS the act** («فعّل وضع رمضان» / «اقفل وضع رمضان»); no
  switch, no autosave. A test opens the screen, edits Iftar, closes it,
  and asserts routine, backup and every scheduled notification are
  identical. Entry: the settings card, gold-edged with «شغّال» when on.
- Guard: «عدّل يومك» is locked while Ramadan is on (gold line) so an edit
  cannot be silently discarded by a later OFF.

**Round 4.2c — escalation alerts on the caregiver screen (built, NOT
device-verified)**
- `CaregiverAlert` + `CaregiverSnapshot.alerts`; `SupabaseCaregiverRemote`
  reads `escalations` (48h, mine, `sent|no_token|failed`, newest first)
  with the dose and medication embedded; `_AlertCard` above the week
  strip — gold while open, ivory + «أكّدها بعدين ✓» once taken, open
  always above resolved. Wording per status as described in Phase 4.
- 13 tests: six screen cases with a fake remote (one alert, resolved,
  skipped, `no_token`, `failed`, none → nothing), ordering open-above-
  resolved, and the pure `alertFromRow` parse.
- Unverified: the nested-embed `.eq` filter on the live project, and what
  a real `sent` row looks like there — every live row is still `no_token`
  until «Next» 4 lands, so the demo shows the in-app wording.

**Round 4.2b part 2 — the Dart side: registering the son's token (built,
NOT device-verified)**
- `lib/data/push/`: three interfaces, `PushTokenService` holding every
  decision in plain Dart, `FirebaseTokenSource` (the only Firebase import;
  Android only — iOS waits on APNs, debt 3) and `SupabasePushTokenRemote`
  (calls `claim_device_token`).
- `NotificationService` now creates the `fakkarni_caregiver` channel, its
  own channel so the son can mute his father's ordinary dose reminders
  without muting the alert that matters.
- Wired in `main.dart` (null when Supabase or Firebase is absent — the app
  is unchanged without either), cleared before sign-out, registered
  eagerly after linking.
- 12 tests with fakes, none touching Firebase, plus the channel-name mirror
  test.
- `firebase_core` ^4.14.0 + `firebase_messaging` ^16.6.0; google-services
  Gradle plugin 4.5.0; **no firebase-bom** (the Flutter plugins carry their
  own versions).
- **Gradle wiring verified 2026-09-15:** `flutter build apk --debug` with
  the google-services plugin applied builds and runs on the Pixel_8
  emulator (API 34) — the Android SDK now exists on this machine. Still
  unverified: a real device token, i.e. `handled 1 / sent` replacing
  `no_token`.

**Rounds 4.2b parts 2–3 — the cloud half is live**
- `0006`–`0009` all applied to the real project, `ALL ESCALATION TESTS
  PASSED` after each. `0008` schedules `fakkarni-escalate` every five
  minutes; `0009` makes an interrupted claim retry after 5 minutes and
  turns the claim into one atomic statement.
- The Edge Function is deployed with the atomic claim
  (`claim_escalation_for_service`); the old INSERT-then-409 version would
  have made `0009` a no-op.
- The only thing standing between a missed dose and the son's phone is a
  registered device token.

**Round 4.2b part 2 — the alert path, verified on the live project**
- `0006_push.sql`: `device_tokens` (token is the PK; writes go through
  `claim_device_token`) + `escalations` (`unique (dose_event_uuid,
  caregiver_id, rung)` is the whole no-duplicate mechanism),
  `private.server_grace_window()` and `private.due_escalations` — the one
  definition of the selection. `0007_escalate_rpc.sql`: a `public` wrapper
  for it, `service_role` only, because `private` is not exposed to
  PostgREST.
- `tests/escalation_test.sql` proved the selection **before** any sending
  code existed: chosen once, second run empty, confirmed/missed (until 0011)/stopped/
  unlinked/pending-link never chosen, +50 no and +60 exactly yes, the
  unique catching a racing second claim, and a second brother still
  alerted after the first.
- `functions/escalate/index.ts`: no imports (plain fetch + Web Crypto),
  three modes (`dry_run`, one event by hand ignoring the clock, bounded
  scan), bearer must equal the service role key, claim-then-send, transient
  FCM failures release the claim and permanent ones delete the dead token.
- `test/data/sync/server_grace_sql_test.dart` holds the 60 in SQL against
  `serverGraceWindow` in Dart, and fails if either moves alone.
- Verified live: `ALL ESCALATION TESTS PASSED`, and a hand invocation
  returned `handled 1 / no_token` — Google accepted the service account,
  the care relationship resolved, the row was claimed. Only token
  registration is missing.
- Also fixed on the way: `0001`–`0003` could never be re-run (the README
  claimed otherwise), and the `serverGraceWindow` invariant was written as
  `>` and tested with a minute subtracted to make `>` pass on an `=`.

**Round 4.2b part 1 — the cloud knows the dose before its time (built)**
- `rescheduleAll` materialises yesterday, today **and tomorrow**;
  idempotent, so re-opening adds nothing.
- `serverGraceWindow` (60) + `syncSlack` (15) beside `graceWindow` (45),
  with the invariant under test.
- Caregiver footer goes gold past `staleAfter` (24h) with «اطمن عليه».
- Foundation test in `test/data/sync/`: one morning open, no further
  touch → every dose of today and tomorrow reaches the cloud as `pending`
  before its time.
- Fixed a latent test bug found on the way: the no-saved-routine case
  pointed its event repository at the wrong database, invisible until
  materialisation reached a day with real doses.

**Round 4.2a — the isolate's writes reach the cloud (built, not yet
device-verified)**
- `SyncService.pushOnce({timeout})` — one bounded attempt over the same
  `push()` body, so there is still exactly one definition of how a row
  goes to the cloud; `backgroundTimeout` is injectable for tests.
- `initSupabaseForIsolate()` beside `initSupabaseAuth()`; the background
  entry point in `bootstrap.dart` builds a `SyncService` without
  `start()` (no listeners, no timers) and calls `shutdown()` in `finally`.
- `NotificationActionHandler.sync` pushes as its last statement. Tests
  assert the last cancel happens before the first upsert, that an
  unlinked device makes zero calls, and that a failing or hanging cloud
  leaves the local write, the cancels and the dirty rows intact.
- Device check pending: `/device` steps 7 and 8.

**Round 3.2a — stable row identity (built)**
- `uuid` on all six tables, v4 backfilled per row, schema v5. Verified by
  SchemaVerifier (v4→v5) and the hand-written v2-file test (v2→v5).

**Round 3.5 — the son's read-only view (built)**
- `CaregiverRemote` + Supabase impl (linked patient via own
  care_relationships, meds, 7 days of dose_events, max server updated_at);
  `CaregiverScreen` (mockup 04 + week strip from 12): 7-day confirmed
  counts, today's list with states verbatim, gold «لسه ما اتأكدتش»,
  «آخر تحديث من موبايل والدك». Entry: «متابعة {الاسم}» on the link screen
  + «افتح المتابعة» after redeem.

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

**Demo prep (chore, no features)**
- Step-trace `debugPrint`s removed from `bootstrap.dart` and
  `notification_actions.dart`. Kept: the isolate-entry and `_onTap` lines
  (see the second-engine note above) and every log inside a `catch` —
  `Handle: ⚠`, `Auth:`, `Care:` — they are the only record of a real
  failure on a path no test reaches.
- `test/app/phone_width_smoke_test.dart`: ~25 screens at 390 wide, text
  ×1.0 and ×1.3, empty and seeded, with the real fonts loaded (the test
  font's 1em glyphs give false overflows). It found and fixed: the
  emergency card's top row, the tab labels, the medication group head.
- `GoldNote` (ink text, gold start edge) replaces gold *text* on ivory
  (≈1.9:1) in redeem / edit routine / edit medication; settings values are
  ink, not gold.
- **Known, not fixed (decisions):** the water
  counter's «٠» reads as a bullet; the empty home shows water above
  «جدول النهاردة» and the «ضيف» FAB covers the empty-state line; the
  notification permission has no in-app lead-in; the caregiver screen
  still uses gold text.

**D4 — entry screen + caregiver account (built)**
- **The root decides from data, never from a role column** (`AppRoot`):
  a local patient (routine saved or sex asked) → the patient app, exactly
  as before; no patient but a locally restored session → `CaregiverShell`;
  neither → `EntryScreen`. Once either a patient or a care link exists,
  the entry screen never appears again. `watchHasPatient` + the auth state
  stream drive it; nothing is written to decide it.
- **Entry screen** (mockup 02's cards, each card is the action, no
  continue button): «التليفون ده ليا» → «نتعرّف عليك» → «ظبّط يومك» →
  «يومك», unchanged. «بظبّط لحد تاني» → the same screens worded about
  the patient: `Say(sex, aboutSomeoneElse: true)` — the first question is
  neutral («اسم والدك أو والدتك إيه؟»), third person after the sex is
  chosen («بيصحى / بتصحى», «يومها», «سنّها كام؟ (لو تعرف)»); the setter's
  own «مش متأكد» stays generic. The choice is held in `AppRoot` memory
  only; after setup the app addresses the patient directly. A «رجوع»
  returns to the entry screen until a patient exists.
- **«ابني أو والدي بعتلي كود»** → `SignInScreen(onCaregiverLinked:)`, which
  explains that this is the only place an account is asked for and offers
  no «اعرض كود الربط» → `RedeemCodeScreen` → «افتح المتابعة» pops `true`
  to the root → `CaregiverShell`. No patient question, no routine, no
  patient met. `signInToLink()` is still called from exactly one line.
  After linking the notification permission is requested once (without it
  the escalation push cannot show on Android 13+) — outside the redeem
  `try`, so a failed permission request never turns a successful link
  into «مقدرناش نكمّل».
- **The son is not a patient.** `CaregiverShell`: two tabs, «متابعة» and
  «الإعدادات»; no «يومك», «ضيف», dose editor, Ramadan, or «طوارئ»
  shortcut (the father's emergency data lives on the father's phone).
  «متابعة» shows the alert cards, the week strip, today's doses and — new —
  the father's medicines with their rules, read from `dose_schedules` /
  `fixed_timings` in the cloud and worded by `domain/wording/rule_wording`
  (the same text the patient sees; the son's side still never resolves an
  anchor). «الإعدادات» is the account (sign-out clears the push token
  first) and «اللغة: عربي». `caregiver_shell_test` walks every tappable
  widget on both tabs and allows only the two tabs and «تسجيل الخروج» —
  mutation-checked with a planted button.
- **Not linked vs offline:** `snapshot()` returning null means "no linked
  patient" → back to the entry screen (a son whose code failed and who
  closed the app); a thrown `CareCircleException` is offline → the existing
  offline sentence stays on the son's home.
- **Unverified live:** the medicines embed
  (`dose_schedules(…, fixed_timings(minute_of_day))`) has never run against
  the real project; RLS should allow it through `can_access_patient`.
  Devices linked as a son **before** D4 went through onboarding, so they
  hold a routine and stay "patient" — reinstall them.

**App icon + Android launch screen (chore)**
- `flutter_launcher_icons` config lives in `pubspec.yaml`, fed by
  `assets/branding/icon-1024.png` (opaque, iOS + legacy Android) and
  `icon-foreground.png` (transparent, mark already at 45.5% for the
  adaptive safe zone — hence `adaptive_icon_foreground_inset: 0`; the
  default 16% would shrink it to ~31%). Re-run with
  `dart run flutter_launcher_icons`, **then `git checkout
  ios/Runner.xcodeproj/project.pbxproj`**: 0.14.4 rewrites
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES` to
  `AppIcon` (a boolean setting); the icon name is already set on the target.
  `test/app/branding_test.dart` fails if either path stops existing.
- Android launch screen is flat `#0A4638` with no mark, like iOS since D1:
  `drawable*/launch_background.xml` for ≤ API 30, and `values-v31` /
  `values-night-v31` (`windowSplashScreenBackground` + a transparent
  `windowSplashScreenAnimatedIcon`) because Android 12+ draws its own
  splash and never reads that drawable. Home-screen name «فكرني» on both
  (`android:label`, `CFBundleDisplayName`).

**Next**
1. Photograph a real handwritten prescription with the key set; tune
   `maxWidth`/`imageQuality` and the prompt from what actually fails
2. Re-run the `/device` checklist for the action buttons specifically: tap
   «أخدته» on the lock screen with the app terminated, then check
   `pending()` grew (Android background isolate + iOS category actions were
   not part of the first device pass)
2. Stop / edit a medication from «يومك» (`stopMedication` exists in the
   repository, no screen calls it)
3. Re-run the `/device` checklist on iOS now that the background engine
   registers plugins — the lock-screen path (and therefore 4.2a's push
   from the isolate) has never actually executed on hardware
4. Build the APK on a machine with the Android SDK, install it, sign in,
   and confirm a `device_tokens` row appears — then invoke `escalate` by
   hand and confirm `sent` instead of `no_token`. Everything upstream of
   the token is proven on the live project; this is the only unverified
   link in the chain — and the first time the caregiver screen's
   `sent` line («السيرفر بلّغك …») renders from a real row
5. Open the caregiver screen against the live project with at least one
   `escalations` row present and confirm the card appears — that is the
   first run of the nested-embed filter in `SupabaseCaregiverRemote`
6. Round 4.3: the son's alert screen (mockup 27); Critical Alerts request

---

## Never do

- Add a dependency to `lib/domain/`
- Persist a resolved clock time for an anchor dose, make `FixedTiming` the
  default, or put a dose-time column on `dose_schedules` (`active_from` is
  the rule's start instant, not a dose time — the one allowed exception)
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
