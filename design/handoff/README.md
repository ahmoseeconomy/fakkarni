# Handoff: FAKRNY / فكّرني — Arabic-first family medication & health companion

## Overview

FAKRNY is an Arabic-first, RTL mobile app for elderly patients in Egypt and the family
member who cares for them. Its organising idea: **prescriptions are written in anchors**
("before breakfast", "before bed"), not clock times. The app asks the patient about his
day once, ever, and every prescription then schedules itself against that day. A dose is
stored as `{anchor: "breakfast", offset: -30}` — never as `{time: "07:00"}`.

33 screens, 3 account types, Arabic + English, a large-type elder mode, and a Ramadan
mode that re-anchors the whole schedule to suhoor and sunset.

---

## About the design files

The files in this bundle are **design references authored in HTML** — working prototypes
that show the intended look, copy, and behaviour. They are **not production code to copy
into the app**.

The task is to **recreate these designs in the target codebase's own environment** —
React Native, Flutter, SwiftUI, Kotlin/Compose, whatever the project uses — following its
established component patterns, navigation, and state layer. If no codebase exists yet,
pick the framework that fits the product (a cross-platform native stack is the obvious
choice for an Egyptian consumer health app) and build there.

What must survive the port exactly: the colours, the type scale, the sizes, the Arabic
copy, and the anchor-based scheduling model. What should not survive: the HTML/CSS
structure, the single-file architecture, or the `renderVals()` pattern — those are
artefacts of the prototype.

### Fidelity: **high**

Every colour, size, radius, weight, and string in the prototype is final and deliberate.
Recreate the UI pixel-for-pixel. Where this document gives a hex value or a px size,
that is the value to ship.

---

## Who is holding the phone

This drives every size decision and must not be softened in the port:

- A 72-year-old man, reading glasses, in a hurry, sometimes at 11pm.
- Body text minimum 20px in the patient-facing flows. Dose names 24px+. **Never below 17px.**
- Tap targets minimum 56px tall. Primary buttons 64px.
- **Two choices per screen maximum.** Never three primary actions.
- No icon-only buttons. Every control carries a word.
- Copy in warm Egyptian colloquial — "بتفطر الساعة كام؟" not "يرجى تحديد موعد وجبة الإفطار".
- **Never use red for a missed dose.** Missing a dose is not a failure to be scolded for —
  use gold and neutral wording. Red is reserved for emergency only.

---

## Brand

The mark is a geometric letter **ف** with a gold dot above it. The dot is the ʼiʻjām dot —
in Arabic manuscripts these were written in gold. **Gold is reserved for the dot, for
reminders, and for the active state. It appears nowhere else.**

The mark is drawn in code, not an image asset:

```svg
<svg viewBox="0 0 120 120">
  <g fill="none" stroke="#F1EFE6" stroke-width="11" stroke-linecap="round">
    <circle cx="76" cy="56" r="17"></circle>
    <path d="M59 56 H40 C24 56 15 68 21 80 C27 91 44 92 55 85"></path>
  </g>
  <circle cx="76" cy="18" r="8" fill="#E9A93B"></circle>
</svg>
```

At 16px and below the letter is dropped and the mark reduces to **a gold dot inside two
ivory rings** (see `FAKRNY Brand Identity` file, board 05).

### Do not
- Use a bell, a pill, a clock, or a heart as an icon — the ف mark and its gold dot carry the identity.
- Colour the letter gold, add a second gold element, rotate the mark, or move the dot.
- Let gold appear on anything that isn't a reminder or an active state.
- Use gradients, drop shadows on the mark, or bevels. Every surface is flat.
- Write formal MSA anywhere in the product.

---

## Design tokens

### Colour

| Token | Hex | Use |
|---|---|---|
| ink | `#122E28` | Primary text, dark surfaces, dark buttons |
| green | `#10715E` | Primary action, active tab, section kickers |
| green deep | `#0A4638` | Splash ground, mark tile, icon background |
| ink deep | `#071A16` | Canvas behind the phone |
| green dark | `#0F3A31` | Dark-screen gradient stop |
| **gold** | `#E9A93B` | **Reminders and active state ONLY** |
| gold soft | `#F1C476` | Gold hover |
| gold text | `#F0D3A0` | Gold copy on dark grounds |
| ivory | `#F1EFE6` | Page ground, text on dark |
| ivory warm | `#EAE7DB` | Cards, chips, secondary fills |
| ivory pale | `#F7F5EC` | Inactive chip fill |
| ivory dim | `#EFEDE3` | Alternate page ground |
| line | `#DFDACB` | Borders, dividers |
| line soft | `#E9E5D8` | Row dividers inside cards |
| muted | `#6E7F76` | Secondary text |
| muted dark | `#43544C` | Disabled button label |
| muted light | `#8B9C93` | Tertiary text, placeholder icons |
| placeholder | `#A5AFA5` | Empty-field text |
| amber | `#D3A21C` | Alert rung 3 (late) |
| orange | `#D9691F` | Alert rung 4 (urgent) |
| red | `#C0202F` | **Emergency only** — SOS button, ambulance, critical rung |
| red deep | `#A81E26` | Emergency screen ground |
| green ok | `#175E39` | Confirmed / taken |
| green ok soft | `#EAF5EE` | Confirmed fill |

Escalation ramp, rung 1 → 5: `#DFDACB` grey → `#10715E` green → `#D3A21C` amber →
`#D9691F` orange → `#C0202F` red.

### Typography

| Role | Family | Weights | Notes |
|---|---|---|---|
| Display / brand | **Alexandria** | 500, 700 | The wordmark and screen titles |
| Body | **IBM Plex Sans Arabic** | 400, 500, 600, 700 | All interface copy |
| Numerals | **IBM Plex Mono** | 500, 600 | Tabular. Times, doses, readings, dates |

Scale in use: 46/38/34 display · 25 screen title · 23 sub-title · 19 section head ·
16.5/16/15.5/15 body · 14.5/14 row label · 13/12.5 secondary · 11.5/11 caption ·
10/9.5 mono kicker (uppercase, `letter-spacing:.14em`).

Arabic numerals are rendered as Arabic-Indic digits (`٠١٢٣٤٥٦٧٨٩`) throughout the Arabic
locale — there is an `ad()` helper in the prototype that converts. Latin digits in English.

### Geometry

Radius: `8` chip · `11–13` icon tile / small button · `14–16` card / input ·
`18` section card · `20–22` large card · `26` sheet top · `44` phone screen ·
`49.5` app icon at 1024 (22.5%).

Spacing: `4 / 6 / 8 / 10 / 12 / 14 / 16 / 18 / 20 / 22 / 26 / 30`.

Shadows are used sparingly and only for elevation off the page:
`0 8px 26px rgba(14,42,51,.1)` card · `0 12px 30px rgba(14,42,51,.18)` menu ·
`0 -14px 40px rgba(0,0,0,.24)` bottom sheet · `0 18px 46px rgba(0,0,0,.28)` modal on dark.

### Device frame

The prototype renders at **414 × 868** inside a phone shell. The scheduling-flow canvas
uses **390 × 844**. Design for 390–414 logical width.

---

## Account types

Exactly three. Every screen's content, permissions, and copy derive from this.

| Type | Arabic | Who | Can |
|---|---|---|---|
| `self` | حساب شخصي | The patient, managing his own file | Everything about himself |
| `owner` | مالك الرعاية | Adult son/daughter who opened the file | Everything, plus grants access to others |
| `invited` | عضو مدعو | Another family member, joined by link | Only what the owner granted |

The invited member joins by **pasting an invite link** copied from the owner's account —
no email signup path. Self and owner sign in with email, Google, or Apple.

Permission differences that must be preserved:
- The invited member's notification rows for glucose readings, reports, and weekly summary
  are **locked and greyed with a 🔒 "مغلق"** — only the owner can open them.
- Missed dose and emergency are 🔒 **"دائمًا"** for everyone — cannot be switched off.
- The owner's +45 min escalation rung is mandatory; the patient's on-time rung is mandatory.

---

## The scheduling model — the core of the product

### Anchors

The day is asked once in **ظبّط يومك** and stored as five anchors, in minutes from midnight:

| Key | Arabic | Default |
|---|---|---|
| `wake` | الصحيان | 06:30 |
| `breakfast` | الفطار | 07:30 |
| `lunch` | الغدا | 14:00 |
| `dinner` | العشا | 20:00 |
| `sleep` | النوم | 23:30 |

Each question offers **three large preset chips above a time wheel** — most people take a
preset and never scroll — plus **"مش متأكد"**, which takes a sane default and never dead-ends.
Progress is five dots, gold for the current one.

### Doses

A dose is `{anchor, offset}`. The resolved clock time is derived, never stored:

```
time = anchors[anchor] + offset
```

The **dose editor** makes the anchor chip row the primary control — eight chips:
قبل الفطار · بعد الفطار · قبل الغدا · بعد الغدا · قبل العشا · بعد العشا · قبل النوم · أول ما أصحى.
Below it, a big − / + offset stepper ("بكام؟ ٣٠ دقيقة") and a live gold preview line
("يعني حوالي ٧:٠٠ ص"). A deliberately secondary text link at the bottom reads
**"أحدد ساعة ثابتة بدل كده"** — the escape hatch exists but is never the default.

**A raw time-picker is never the primary control anywhere in this flow.**

### When the prescription gives no time

Two settings decide what the AI may assume, set during onboarding and changeable later:

**Policy** (screen 21, الاسم والسن):
1. اسألني في كل مرة — nothing is scheduled without explicit approval.
2. **افترض من يومه وعلّم عليها** (default) — place on the nearest anchor, flag the row in gold until reviewed.
3. افترض من غير ما تسأل — for familiar monthly repeats, no flag.

**Fallback rules** (screen 22, ظبّط يومك):
- Before / after / with food, plus a ± minutes stepper. "With food" forces the gap to 0.
- A live table showing how 1× / 2× / 3× daily map onto anchors and resolve to times —
  it recomputes instantly when the anchors change.
- Duration when unwritten: ٧ أيام · لحد ما العلبة تخلص · مستمر · **اسأل الدكتور**.
- A gold-bordered live example on `Amebazole 1 gm — 1×1` showing the final result and a
  line stating whether it will be flagged, asked, or set silently — following the policy above.

### Ramadan mode

Re-anchors the day to **السحور · الفطار (المغرب) · النوم**, then shows exactly what will
move — "٤ أدوية هتتحرك" with a before → after list per medicine. **Nothing changes until
the user taps فعّل وضع رمضان.** Toggleable from settings, with the card border turning gold
when active and the sub-line reading the current state.

---

## Screens

33 in total. Numbered as they appear in the prototype's screen picker.

| # | Key | Arabic | Purpose |
|---|---|---|---|
| 1 | `splash` | شاشة البداية | Animated mark build, 1.6s, hands off to the app |
| 2 | `onboard` | اختيار نوع الحساب | Pick one of the three account types |
| 3 | `login` | تسجيل الدخول | Email / Google / Apple, or paste an invite link |
| 4 | `home` | الرئيسية | What's waiting: next dose, water widget, day summary |
| 5 | `capture` | تصوير الروشتة | Camera with corner guides and **live OCR** highlighting lines as they're read |
| 6 | `review` | مراجعة الذكاء | Confirm what the AI understood — edit icon per field, add-manual row |
| 7 | `labshot` | تصوير تقرير تحليل | Capture a lab report, multi-page |
| 8 | `labread` | قراءة التقرير | Flags values outside **his** usual range — no recommendation, ever |
| 9 | `meds` | جدول الأدوية | Time groups, per-group confirm, voice + manual add icons |
| 10 | `alert` | تنبيه متصاعد | Full-screen dose reminder on the dark ground, 5-rung ladder |
| 11 | `checkup` | دورة الفحص | The recurring check cycle |
| 12 | `calendar` | التقويم | Month / week view with type filters |
| 13 | `records` | الملف الصحي | Search by name/doctor/date, ⋯ menu → remove with confirm and restore |
| 14 | `vitals` | قياس السكر | **Blood glucose only** — voice or typed entry |
| 15 | `circle` | دائرة الرعاية | Members, permissions, invite link with copy + share icons |
| 16 | `handoff` | صفحة الطبيب | Visit summary: meds, 30-day readings, latest labs, the family's questions |
| 17 | `nearby` | قريب منك | Map with pins + cards: distance, rating, open/closed, call, directions |
| 18 | `elder` | نمط كبار السن | Large-type mode: greeting, one dose card, ✅ تم, 📞 call, two tabs |
| 19 | `emergency` | الطوارئ | Blood type, allergies, chronic, meds, contacts, ambulance |
| 20 | `adddose` | إضافة دواء وجرعة | Name, dose, frequency, food, duration, reminder |
| 21 | `about` | الاسم والسن | Name, sex, age + **the AI assumption policy** |
| 22 | `routine` | ظبّط يومك | The five anchors + **the fallback rules** |
| 23 | `dose` | محرّر الجرعة | Anchor chips + offset stepper + live preview |
| 24 | `dayrail` | جدول النهاردة | Vertical rail: green anchor nodes, gold-edged dose cards between them |
| 25 | `ramadan` | وضع رمضان | Re-anchor preview, before → after per medicine |
| 26 | `notify` | التنبيهات | Per-role notification groups + 5 independent escalation rungs + quiet hours |
| 27 | `stages` | بطاقة التنبيه · ٥ مراحل | The alert-card component shown at all five rungs, five alert types |
| 28 | `manual` | إدخال يدوي | Five typed-entry forms: imaging, visit, lab, prescription, booking |
| 29 | `archive` | الحالات السابقة | Chronological timeline, filter by type and period |
| 30 | `export` | استخراج الملف | Date range, section toggles, per-section 👁 visible / 🙈 hidden |
| 31 | `expview` | معاينة الملف | Exactly what the recipient will see, before sharing |
| 32 | `emcard` | بطاقة الطوارئ | Lock-screen card — readable without unlocking |
| 33 | `settings` | الملف والإعدادات | All of the above, plus the Ramadan switch |

### Screens that carry the most design weight

**5 · تصوير الروشتة — live OCR.** Corner-guided frame over the camera. As lines are
recognised they light up inside the frame: dashed 1.5px `rgba(255,255,255,.28)` outline
while unread, solid `#EAE7DB` with a `rgba(234,231,219,.18)` fill once read. A counter
badge at the bottom reads "يقرأ الآن · ٣/٤ سطور" with a pulsing dot. Secondary options:
"اختار من الصور" and "أكتبها بإيدي".

**6 · مراجعة الذكاء — the most important screen in the app.** One row per medicine:
name in LTR mono, the resolved time in Arabic numerals, and a chip showing **the rule, not
the time** — "الفطار − ٣٠ د". Each row has its own عدّل with an edit icon. **One row must
render a low-confidence state**: a gold left border and the line "مش متأكد من دي — راجعها".
The AI admitting doubt is a feature — design it to look considered, not broken.
Two buttons of **equal visual weight**: "تمام، ظبّطهم" and "أعدّل". Never make أعدّل a faint
ghost link; never nudge a person into confirming a medication schedule they haven't read.
Real medicine names throughout: Telfast 180 mg, Antodine 40 mg, Amebazole 1 gm, LINEX Adult cap.

**8 · قراءة التقرير.** Flags any value outside the patient's own usual range and says so
plainly. **It never recommends anything** — no advice, no diagnosis, no "consider". It
states the number, the range, and the delta, and stops.

**10 · تنبيه متصاعد.** Dark gradient ground. Stage kicker, "مرّت ١٥ دقيقة على موعد الجرعة",
a white card with the medicine, then ✅ تم التناول / ⏰ تأجيل ١٥ د / ❌ تخطّي / ❓ لا أذكر.
Below, the five-rung ladder with the current rung highlighted amber. A voice-prompt line
at the bottom. **No red for the missed dose itself.**

**24 · جدول النهاردة.** A vertical rail down the **right** edge (RTL). Anchors are green
nodes with labels; doses are gold-edged cards attached to the rail between them. Pinned at
the top, the next dose, large: "الجاية: Antodine — كمان ٢٥ دقيقة" with a 64px "أخدته"
button. Taken doses collapse to a quiet checked line — visible, not deleted.

**27 · بطاقة التنبيه.** One card component, rendered at all five rungs stacked vertically
so the ramp is visible at a glance. Five alert types switch the content: دواء · ميعاد دكتور ·
تحليل · أشعة · متابعة. Each card carries the rung number, the rung name, a progress ramp
(`linear-gradient(90deg, accent N×20%, #DFDACB N×20%)`), the medicine, the state line, and
a rung-coloured CTA.

**32 · بطاقة الطوارئ.** Renders as a lock-screen card on a dark red-green gradient: clock,
then a white card with blood type, allergies, chronic conditions, current medicines, then
contacts with call buttons, then a pulsing ambulance button.

---

## Interactions & behaviour

### Splash — 1.6s, authored

| t | Event |
|---|---|
| 0.00s | Flat `#0A4638` ground, nothing else — identical to the static launch image |
| 0.10s | The ف strokes draw: bowl first, then tail · 0.55s ease-out, `stroke-dashoffset` 120 → 0 |
| 0.65s | The gold dot appears and settles 4px downward · 0.25s |
| 0.85s | **One** halo ring expands from the dot, scale 0.5 → 2.6, opacity 0.75 → 0 |
| 0.95s | "فكرني" rises 8px into place · 0.35s ease-out |
| 1.60s | The group scales to 1.04 and fades over 0.3s as the first screen appears beneath |

The app is **never gated on this screen** — if it's ready in 300ms, cut. The static launch
image (iOS `1170×2532`, Android `1080×2400`) is the **flat ground alone**, so the cut from
the OS launch screen is invisible.

### The gold dot at rest

A 3.4s loop: still for the first 72%, then one beat — dot 1 → 1.18 → 1 over 0.5s with a
halo expanding 0.5 → 2.6 and fading. It should read as a quiet intermittent reminder, a
heartbeat with a long rest — not a pulse, and not a loading spinner.

### Other motion

- Water ring: live countdown ticking every second, circular progress via `stroke-dashoffset`.
- Bottom sheet: `slideUp .28s ease` with a `rgba(11,42,51,.55)` scrim, tap-outside to close.
- Row menus and confirmations: `fadeIn .15s ease`.
- Emergency and ambulance buttons: `pulseRing 2.6s infinite`.
- All animation is disabled under `prefers-reduced-motion`, resolving to the final state.

### Destructive actions

Removing a record: ⋯ menu → red confirm panel → the row stays visible, struck through and
faded to 45%, tagged "حُذف", with a ↺ restore. Copy: "يُنقل إلى المحذوفات ٣٠ يومًا قبل الحذف النهائي."

---

## State

The prototype holds everything in one flat state object. In the real app, split these into
the appropriate stores; the shape is what matters.

**Identity & session** — `persona` (`self|owner|invited`), `lang` (`ar|en`), `registered`,
`loginEmail`, `inviteLink`, `inviteCopied`, `pName`, `pSex` (`m|f`), `pAge`.

**The day** — `day` (anchor overrides in minutes), `ramadan`.

**Scheduling policy** — `aiPolicy` (0–2), `fbFood` (0=before, 1=after, 2=with),
`fbGap` (minutes, 0–120 in 15s), `fbDur` (0–3).

**Dose editing** — `dAnchor` (0–7), `dOffset` (minutes), plus the manual-add fields
`dName / dUnit / dFreq / dFood / dDur / dRemind / dAdded`.

**Adherence** — `doses` (confirmed by slot), `elderTaken`.

**Notifications** — `notif` (per-role keyed map, incl. `stage:<persona>:<rung>`), `quiet` (0–2).

**Records** — `search`, `menuFor`, `delFor`, `deleted`, `recTab`, `archFilter`, `archPeriod`.

**Export** — `expRange` (0–3), `expOff` (per-section), `expHide` (per-section).

**Ambient** — `water` (cups 0–8), `waterEvery` (1|2|3 hours), `tick` (1s interval),
`ocr` (0–3, 1.1s interval), `elder`, `sheetOpen`, `stageType`.

Two intervals run for the live behaviour: a 1s tick for the water countdown and a 1.1s
tick for the OCR line-by-line reveal. Clear both on unmount.

---

## Localisation

Every string exists in Arabic and English, and the whole layout mirrors. Notes for the port:

- Arabic is the primary locale. English is a courtesy — design and review in Arabic first.
- Use logical properties (`inset-inline-start`, `text-align: start`) rather than left/right.
- Arabic-Indic digits in the Arabic locale, Latin digits in English. Times, doses, and
  measurements are always mono and tabular in both.
- Latin medicine names stay LTR and mono inside RTL text — do not transliterate them.
- The tone is Egyptian colloquial, warm and familiar. Never MSA, never clinical.

---

## Assets

**None.** There are no image files. The mark, every icon, the map, and the QR block are
all drawn as inline SVG in the design files. The only external dependency is the two
Google Fonts families — Alexandria and IBM Plex Sans Arabic — plus IBM Plex Mono for
numerals. Bundle all three with the app rather than fetching them at runtime.

---

## Files in this bundle

| File | What it is |
|---|---|
| `FAKRNY App.dc.html` | **The primary reference.** All 33 screens, 3 account types, both languages, elder mode. Open it and use the sidebar picker to walk every screen. |
| `FAKRNY Prototype.html` | The same app as a single self-contained file — opens offline in any browser, no server. Hand this to anyone who just needs to *see* it. |
| `FAKRNY Brand Identity.dc.html` | 8 boards: the animated splash at three device sizes with its timing table, the static launch asset, the animated lockup, the app icon at four sizes, the reduction proof down to 16px, the lockups, monochrome, and the misuse rules. |
| `FAKRNY Scheduling Flow.dc.html` | The nine scheduling screens at 390×844 in light **and** dark, side by side — the most precise reference for the anchor model. |

Open the `.dc.html` files directly in a browser. To read the source, the markup is the
template block and the logic is the class at the bottom of each file.
