# Fakkarni (فكرني) — Project Guide

Arabic-first (RTL) medication reminder app for elderly patients in Egypt.
Its differentiator: when a **critical** dose is missed, the app escalates and
finally **places a real phone call** to the caregiver (the patient's adult child).

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

5. **A confirmation cancels escalation immediately, at any stage** — including
   while the phone is already ringing. A few seconds of lag here means a
   needless call, which is worse than a late one.

6. **No medical advice, ever.** Default offsets (30 min before food, 15 min
   before bed) are editable operational conventions, not clinical guidance. If a
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
- **Gold (`F.gold`) is only for reminders and the active state.** Anywhere else
  it stops meaning anything. The mockups show a coral FAB in the bottom bar —
  build that FAB in green, not coral. Gold must be the only colour that pops.
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
  core/theme/tokens.dart      brand colours + elderly-first sizing (class F)
  core/notifications/         NotificationService — local scheduling; tap → lastPayload
  data/db/                    drift (SQLite) v3: patients, day_routines, medications,
                              dose_schedules (timing_kind), fixed_timings, dose_events
  data/repositories/          routine / medication / dose_event
  data/services/              reminder_plan (pure: IDs, window, payload)
                              reminder_scheduler (engine → sink), reminder_sink
                              notification_actions (lock-screen «أخدته»/«فكّرني بعدين»)
  app/                        AppScope (services), AppRoot (onboarding | today,
                              opens ReminderScreen on tap), bootstrap.dart
                              (buildServices + background action entry point)
  features/onboarding/        5 routine questions
  features/medication/        add medication (anchor chips + offset stepper)
  features/today/             «يومك» — next dose card + day rail
  features/routine/           EditRoutineScreen — change any anchor after onboarding
  features/reminder/          ReminderScreen — أخدته / فكّرني بعد ربع ساعة / مش هاخده
test/                         144 passing
```

**The day starts at wake, not midnight.** `minutesFromDayStart` is
`(anchor - wake + 1440) % 1440`, so a 1 AM bedtime lands 18 hours *after*
waking rather than 6 hours before it. A fixed time follows the same rule:
`resolveFixed` puts a 1 AM fixed dose at the *end* of the routine day (next
calendar date), and otherwise never moves it. Both kinds resolve to the same
minute-keyed map, so a fixed 2:00 PM and «قبل الغدا − ٣٠» at 2:00 PM merge
into one `Reminder` like any other pair.

**Schema changes migrate in place — never wipe.** This database holds real
patients' schedules. `onUpgrade` turns foreign keys off outside the
transaction (the PRAGMA is a no-op inside one), runs every step inside one
transaction, and turns them back on; `beforeOpen` re-asserts them.
`test/data/migration_test.dart` opens a hand-written v2 database with anchor
rows and asserts every schedule and event survived — add a case there for
every future version.

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
critical dose calls for a phone call, and `cancelAll()` would silently take
that escalation down while merely rebuilding a routine — so it is never used. Any new feature that schedules notifications
must claim a band and filter cancellations by it the same way.

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

**Next**
1. Re-run the `/device` checklist for the action buttons specifically: tap
   «أخدته» on the lock screen with the app terminated, then check
   `pending()` grew (Android background isolate + iOS category actions were
   not part of the first device pass)
2. Stop / edit a medication from «يومك» (`stopMedication` exists in the
   repository, no screen calls it)
3. Phase 4 groundwork: escalation band, caregiver contact, the call

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
- Invent a medication duration, dosage or timing
