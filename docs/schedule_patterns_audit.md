# Schedule patterns — audit (25 Sep 2026)

**Audit only.** No app code and no migration were written for this. The
old app supports daily, specific weekdays, every N days, every N hours,
as-needed (PRN), cyclic (e.g. 21 on / 7 off) and once. Fakkarni supports
daily and once in the engine, on top of anchors (meal/routine + offset) and
the fixed-clock exception. This document is what each missing pattern would
cost, where it would touch, and what it must never touch.

---

## 0. How the machine works today (the facts every section below leans on)

| Piece | Where | What matters for new patterns |
|---|---|---|
| Recurrence | `DoseRepeat { daily, once }` + `startDate` + `durationDays` in `lib/domain/scheduling/dose_schedule.dart`; `DoseSchedule.isActiveOn(day)` | **The single gate.** `ScheduleEngine.remindersForDay` asks `isActiveOn` for every schedule, and everything downstream (reminders, dose rows, ladder, repeats, adherence, the son's view) only ever sees what the engine emitted. |
| Timing | `AnchorTiming` / `FixedTiming`, `resolveTime` / `resolveFixed`, day starts at wake | One schedule resolves to **one minute per routine day.** Same-minute doses merge into one `Reminder`. |
| Dose rows | `DoseEventRepository.materializeDay`, called by `ReminderScheduler.rescheduleAll` for yesterday, today, tomorrow | Rows exist only for what the engine emitted. **Key is `(dose_schedule_id, routine_day)`**, unique locally (`tables.dart`, `uniqueKeys {doseScheduleId, routineDay}`) and in the cloud (`unique (dose_schedule_uuid, routine_day)` in `0001`). **A schedule can produce at most one dose per routine day.** |
| Notification window | `planWindow`, `reminderWindowDays = 7`, `maxPendingReminders = 24` (nearest 24) | Horizon = 24 ÷ distinct reminder minutes per day. |
| iOS budget | `iosPendingLimit = 64` = 24 doses + 14 ladder (`maxPendingEscalations`, nearest 7 reminders × 2 rungs) + 20 repeats (`maxPendingRepeats`, «يتكرر» = 3 per reminder → nearest ~6; «مستمر» = up to 10 → nearest 2) + 2 snooze + 2 fasting + 2 checkup | Every band is capped; the dose window is what shrinks. |
| Local ladder | +15 / +30 from the original minute, built from `now − 45` | Derived from the same planned reminders. |
| Server escalation | `private.due_escalations` (latest body in `0025`) selects `dose_events` in `pending`/`missed` past `server_grace_window()` (60) | Reads **dose rows only** — never schedules. A pattern that never creates a pending row can never escalate. |
| Sweep | `sweepMissed` flips `pending` → `missed` at +45 | Only touches `pending` rows. |
| Sync | `_pushDoseSchedules` sends `repeat` (and timing); cloud CHECK `repeat in ('daily','once')` (`0001`) | **Any new repeat value is rejected by the cloud until a migration widens the CHECK.** |
| Adherence | `lib/domain/adherence/adherence.dart` | Day with no rows = neutral. Off-days of any pattern are neutral **for free**, as long as the engine emits nothing on them. |
| Stock | `StockRepository._dosesPerDay` and the son's `medicationFromRow` count **daily** schedules only | Days-left needs an average doses-per-day for non-daily patterns. Decrement happens only on `taken` (`_setState`), so it is pattern-agnostic. |
| Ramadan | `ramadanRoutine` moves anchors; fixed doses stay | Patterns that decide *which days* are orthogonal to Ramadan; patterns that decide *which minutes* must say what happens to fixed clock doses in fasting hours. |
| Golden plan | `test/data/appointment_guard_test.dart` (8 meds × 3 daily doses, identical plan with/without appointments), `reminder_plan_test`, `reminder_repeat_test` | Every change below must leave these byte-identical. |

**Current gap worth fixing first:** `DoseRepeat.once` exists in the domain and
the cloud accepts it, but **nothing in `lib/features` or `lib/data` ever
passes it** — every write goes through `addMedicationWithDoses(repeat: daily)`.
The prescription reader maps «اليوم فقط» to `durationDays: 1`, which behaves
the same for a single-dose day. So "once" is supported by the engine and not
reachable from the UI.

---

## 1. Specific weekdays («السبت والتلات والخميس»)

1. **Anchor model / Ramadan.** Orthogonal: the pattern picks *days*, the
   anchor still picks the *minute*. «قبل الفطار − ٣٠» on Sat/Tue/Thu works as
   today, and moves with Ramadan like any anchor. Weekday is the **routine
   day's** weekday (a 1 AM bedtime dose belongs to the day before) — this
   falls out of `isActiveOn(routineDay)` automatically.
2. **Files.**
   - Change: `dose_schedule.dart` (a `weekdays` bitmask, 7 bits, and one line
     in `isActiveOn`); `tables.dart` `DoseSchedules` + a `from < 29` step and
     `migration_test` / `uuid_migration_test` cases; `medication_repository.dart`
     (`doseScheduleFromRow`, `addMedicationWithDoses`, `MedicationWrite`);
     `sync_service.dart` `_pushDoseSchedules` (+ `_optionalColumns`);
     `rule_wording.dart` (spoken and schedule wording, used by the son);
     `add_medication_screen.dart` (a «كل يوم / أيام معيّنة» row, chips for the
     seven days); `supabase_caregiver_remote.dart` `medicationFromRow`
     (wording + stock average); `StockRepository._dosesPerDay` (average);
     `MedicationChangePayload` if the nurse may add such a medicine.
   - Untouched: `ScheduleEngine` body, `planWindow`, `planEscalations`,
     `planRepeats`, `materializeDay`, `sweepMissed`, the ladder, notification
     ids, `due_escalations`, the adherence calculator, the stock decrement.
3. **Budget.** Never more reminders than daily; usually fewer. On a
   Sat/Tue/Thu pattern the 7-day window holds at most 3 of that medicine's
   days, so horizon only grows. No new band.
4. **Escalation:** yes, exactly like daily (real doses on real days).
   **Adherence:** off-days have no rows → neutral, streak neither broken nor
   extended — correct with no calculator change. **Stock:** days-left must
   use doses-per-week ÷ 7, otherwise a 3-days-a-week medicine reads as
   running out 2.3× too fast.
5. **Server:** `0032`: `dose_schedules.weekdays smallint null` and widen the
   `repeat` CHECK (or keep `repeat='daily'` + a nullable mask — preferred, no
   CHECK change). `due_escalations` unchanged.
6. **Risk: low.** Tests: property test that `isActiveOn` is identical to today
   for every existing schedule over 400 days; a golden plan for a Sat/Tue/Thu
   medicine (ids, instants, ladder, repeats) across two weeks and a DST
   change; the existing golden plans byte-identical; adherence neutral on
   off-days; stock days-left on 3/7.

## 2. Every N days («يوم ويوم», «كل ٣ أيام», weekly)

1. **Anchor / Ramadan.** Same as weekdays: days by the pattern, minute by the
   anchor. Phase is counted from `startDate` in **routine days** using UTC
   date arithmetic (`epochDayOf`-style) so a 23-hour DST day does not shift
   the cycle.
2. **Files.** Same list as weekdays, with `intervalDays` instead of a mask
   (`isActiveOn`: `(day − start) % N == 0`). If weekdays lands first this is
   one more field on the same plumbing.
3. **Budget.** Fewer reminders than daily. Weekly: one reminder in a 7-day
   window. Notification ids repeat every 32 days and the window is 7, so
   N > 7 is still safe (ids are derived from the day, not the pattern).
4. **Escalation:** yes. **Adherence:** off-days neutral. **Stock:** 1/N doses
   per day on average.
5. **Server:** `dose_schedules.interval_days smallint null` (same migration as
   weekdays). `due_escalations` unchanged.
6. **Risk: low.** Tests: golden plan for «يوم ويوم» over 30 days including a
   DST boundary and an edit of `startDate`; `isActiveOn` property test;
   existing golden plans byte-identical.

## 3. Cyclic («٢١ يوم وأسبوع راحة»)

1. **Anchor / Ramadan.** Same as every-N-days (days only). Rule 3 still
   holds: the cycle repeats forever unless `durationDays` says otherwise —
   never inferred.
2. **Files.** Same plumbing, fields `cycleOn` / `cycleOff`
   (`isActiveOn`: `(day − start) % (on + off) < on`). The form needs to say
   which day of the cycle today is, or «بدأت الشريط إمتى؟» — that is the
   `startDate` the phase counts from.
3. **Budget.** ≤ daily. Nothing new.
4. **Escalation:** yes on on-days. **Adherence:** the 7 off-days are neutral
   — the streak survives the break (exactly what the brief asks for).
   **Stock:** average on/(on+off); and during the off week the refill alert
   should not fire earlier than daily-math says — the average handles it.
5. **Server:** `cycle_on smallint null, cycle_off smallint null`. Unchanged
   escalation.
6. **Risk: low–medium** (the only subtle part is the UI for "where am I in
   the cycle"). Tests: golden plan across two full cycles; streak across an
   off week; existing golden plans byte-identical.

## 4. Every N hours («كل ٨ ساعات»)

The one pattern that collides with the data model, so it splits in two.

**4a. N divides 24 (2, 3, 4, 6, 8, 12).**
1. **Anchor / Ramadan.** This is clock time by nature, so it is the
   fixed-clock family: q8h from 06:00 is three `FixedTiming` schedules
   (06:00, 14:00, 22:00) on one medication. **This already works today** —
   «كام مرة» + «ساعة محددة» writes one fixed schedule per dose, and
   `_spreadFrom` even spaces them across the waking day. What is missing is a
   preset («كل ٨ ساعات، أول جرعة الساعة …») that fills the rows at exact
   24/N spacing (not waking-day spacing). In Ramadan fixed doses do not move;
   a dose that lands in fasting hours is a clinical question, so the app
   says nothing new — the Ramadan preview already lists fixed doses as
   unmoved.
2. **Files.** `add_medication_screen.dart` only (a preset that writes N rows
   through the existing `addMedicationWithDoses(timings: …)`), and
   `rule_wording.dart` if the son should read «كل ٨ ساعات» instead of three
   clock lines (optional; can be derived from the set of fixed minutes).
   **Engine, schema, sync, server, ladder, adherence and stock are
   untouched** — each dose is its own daily schedule, one row per routine
   day, so the unique key holds and stock's daily count is already right.
3. **Budget — this is the real cost.** Horizon = 24 ÷ distinct minutes/day:

   | Case | Distinct minutes / day | Dose horizon (24 slots) | Ladder cover (7 reminders) | «يتكرر» repeats (20 ÷ 3) |
   |---|---|---|---|---|
   | 1 med q8h | 3 | 7 days (window cap, 21 slots) | ~2.3 days | ~2 days |
   | 1 med q4h | 6 | 4 days | 28 h | 24 h |
   | 2 meds q6h, same clock | 4 (merged) | 6 days | ~1.75 days | 1.5 days |
   | 2 meds q6h, offset 1 h | 8 | 3 days | 21 h | 18 h |
   | 3 meds q4h, not aligned | 18 | **1.3 days** | 9.3 h | 8 h |
   | 3 meds q4h, aligned | 6 | 4 days | 28 h | 24 h |

   Worst realistic case (three q4h medicines at different clocks) leaves
   **about 32 hours** of reminders on an iPhone if the patient never opens
   the app or confirms. That is debt 0c (the silent horizon) turned from
   "about five days" into "about a day". Mitigations, in order: the preset
   aligns new q-hour medicines to an existing clock when one exists (merging
   is free — same minute = one notification); every confirmation already
   renews the window; and a line in the form when the total distinct
   minutes/day passes ~8 («المواعيد الكتير دي محتاجة تفتح التطبيق أو تأكّد
   من الإشعار كل يوم عشان التذكير يفضل شغّال» — operational, not medical).
4. **Escalation:** yes, per dose. **Adherence:** each dose is a normal
   daily row. **Stock:** correct already (N rows per day).
5. **Server:** none.
6. **Risk: low for code, medium for the iOS horizon.** Tests: preset writes
   exactly 24/N fixed schedules at 24/N spacing; golden plan for 1× q8h and
   3× q4h showing the horizon numbers above; existing golden plans
   byte-identical (no engine change means this is automatic, but pin it).

**4b. N does not divide 24 (q5h, q36h).** Times drift day to day, a
schedule fires 0–5 times per routine day, and the `(schedule, routine_day)`
unique key cannot hold it. It needs an instant-based series (start instant +
k·N), a new dose-row key (an occurrence index or `scheduled_at` in the
key) locally and in the cloud, changes to `materializeDay`, the id
derivation (minute-of-day still works, but the engine's per-day map does
not), and the son's wording. **High risk, low frequency in the target
population. Leave out of v1.**

## 5. As-needed (PRN, «عند اللزوم»)

1. **Anchor / Ramadan.** No time at all — nothing to anchor, nothing Ramadan
   moves.
2. **Files.**
   - Change: `DoseRepeat` gains `asNeeded` (or a medication-level flag);
     `isActiveOn` returns **false** for it, always — so the engine never emits
     it, and therefore `materializeDay` never writes a row, `planWindow` never
     schedules, the ladder and repeats never exist. A new local table
     `prn_intakes` (medication, taken_at, amount, uuid, sync columns) + drift
     step; a «أخدت جرعة» button on the medication card and on «يومك»'s
     medicine list; `StockRepository` decrement on a logged intake (a new
     explicit call — **not** through `_setState`, which is for dose rows);
     sync push for the new table; the son's and nurse's read-only log; form
     option «عند اللزوم».
   - Untouched: engine body, `materializeDay`, `planWindow`, ladder, repeats,
     `sweepMissed`, `due_escalations`, adherence calculator.
3. **Budget:** zero pending notifications. Frees nothing, costs nothing.
4. **Escalation: never.** The guarantee is structural — PRN never produces
   a `dose_events` row at all, so `due_escalations` (which reads only
   `dose_events`) cannot see it. It must **not** be modelled as dose rows
   inserted as `taken`: the unique key allows one per day and a second
   intake would collide, and any future path that writes `pending` would
   escalate. **Adherence:** excluded entirely (no rows → neutral; the card
   is about scheduled medicines). **Stock:** decrements only when an intake
   is logged. No «max per day» line unless the paper says it, and then only
   as the paper's words (rule 6).
5. **Server:** `0032`/`0033`: `prn_intakes` table (RLS on the 0005 pattern:
   owner writes, circle reads via `can_access_patient`), and the widened
   `repeat` CHECK. `due_escalations` unchanged — and a guard test that its
   body never mentions `prn_intakes`.
6. **Risk: medium** (new table, sync, UI in three places, stock hook).
   Tests: a PRN medicine produces no reminders, no dose rows, no ladder, no
   repeats over 30 days (golden); logging decrements stock once per intake
   and never below 0; adherence ignores it; `due_escalations` guard; existing
   golden plans byte-identical.

## 6. Once («مرة واحدة»)

1. **Anchor / Ramadan.** Already in the engine: `isActiveOn` returns true on
   `startDate` only. Anchors and Ramadan behave as for any dose.
2. **Files.** UI only: a «مرة واحدة» choice in the add form (and the nurse
   draft) that passes `repeat: DoseRepeat.once`; optionally let the
   prescription reader map «اليوم فقط» to `once` instead of
   `durationDays: 1` (same behaviour for one day; cleaner wording). Engine,
   schema, sync (cloud already accepts `once`), server: untouched.
3. **Budget:** one reminder, then nothing.
4. **Escalation:** yes on that day. **Adherence:** one day of rows, then
   nothing (neutral). **Stock:** trivially correct.
5. **Server:** none.
6. **Risk: very low.** Tests: a `once` medicine emits exactly one reminder,
   one row, one ladder; existing golden plans byte-identical.

---

## Shared rules for any of these

- **One gate.** Every day-level pattern (weekdays, every N days, cyclic,
  PRN, once) is a change to `isActiveOn` and nothing downstream. If a design
  needs to touch `planWindow`, `materializeDay`, the ladder or
  `due_escalations`, it is the wrong design (4b is the one honest
  exception, and it is out of v1).
- **Cloud first.** A new `repeat` value or column is rejected by the cloud
  CHECK today; the migration must run before a build that pushes it, and the
  push should put new columns in `_optionalColumns` so an un-migrated
  project still takes the row.
- **The son never resolves.** He reads `dose_events` and the wording; new
  patterns only add wording (`rule_wording.dart`), never scheduling on his
  side (`no_scheduling_imports_test`).
- **Stock average.** Replace the "count daily schedules" rule in both
  `StockRepository` and `medicationFromRow` with one pure
  `averageDosesPerDay(schedules)` in `domain/medication/stock.dart`, so the
  patient and the son cannot disagree.
- **Byte-identical proof.** For every pattern round: the three existing
  scheduling suites green with no edits, plus a property test that
  `isActiveOn` for every `daily`/`once` schedule is unchanged over 400 days.

## Recommended order (smallest risk, biggest value first)

| # | Pattern | Why this position | Estimate |
|---|---|---|---|
| 1 | **Every N hours, N ∣ 24** (preset over existing fixed schedules + the budget line) | Common for antibiotics; no engine, schema or server change | 1 day |
| 2 | **Once** (expose it) | Already in the engine; UI only | 0.5 day |
| 3 | **Specific weekdays** | Real demand (injections, vitamins); builds the shared recurrence plumbing + migration + stock average | 2–3 days |
| 4 | **Every N days** | One field on the plumbing from 3 | 1 day |
| 5 | **Cyclic** | Same plumbing; the "where am I in the cycle" question is the only real work | 1.5 days |
| 6 | **PRN** | New table, sync, three UIs, stock hook, circle view | 4–5 days |

**Leave out of v1:** every-N-hours where N does not divide 24 (needs a new
dose-row key end to end); PRN «max per day» guidance beyond the paper's own
words; editing a cyclic phase mid-cycle (start a new schedule instead);
the prescription reader proposing weekday/cyclic/PRN patterns (rule 4 —
each would be flagged for review anyway, so add it after the manual paths
have shipped).

Estimates include tests, the migration file and CLAUDE.md, and exclude a
device pass (every item needs one on iOS for the pending-notification
count, 1 and 6 especially).
