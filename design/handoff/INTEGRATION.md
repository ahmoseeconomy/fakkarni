# Integration guide — building the FAKRNY frontend on an existing backend

Read `README.md` first. That file is the design specification: colours, type, sizes, all 33
screens, the anchor scheduling model, and the rules that must not be broken. This file is
about wiring that UI to a backend that already exists.

---

## The one rule that decides your data model

**A dose is stored as `{anchor, offset}` — never as a clock time.**

```json
{ "medicine_id": 41, "anchor": "breakfast", "offset_minutes": -30 }
```

The clock time is *derived* at read time from the patient's own day:

```
resolved_time = patient.day[anchor] + offset_minutes
```

If your backend currently stores `dose.time = "07:00"`, that is the one schema change worth
making before building the UI. Everything in this design follows from it:

- When the patient changes his breakfast time, **every** dose anchored to breakfast moves.
  No migration, no recalculation job — the times were never stored.
- Ramadan mode is a different set of anchor values, not a different set of doses.
- The AI can schedule a prescription that says "before breakfast" without inventing a time.

If the schema can't change, keep a derived `resolved_time` column as a cache, but let
`{anchor, offset}` be the source of truth and recompute on any anchor edit.

---

## What the frontend needs from the backend

The prototype holds everything in one state object. Below is that state grouped into the
resources a real API would expose. Names are suggestions — match your existing conventions.

### `GET/PATCH /me`

| Field | Type | Notes |
|---|---|---|
| `account_type` | `self` \| `care_owner` \| `invited` | Drives every screen's content and permissions |
| `name` | string | Asked on screen 21 |
| `sex` | `m` \| `f` | Changes all Arabic gendered copy — see "Gendered copy" below |
| `age` | int | |
| `locale` | `ar` \| `en` | Arabic is primary |
| `elder_mode` | bool | Large-type mode (screen 18) |
| `ramadan_mode` | bool | Toggled from settings |

### `GET/PATCH /me/day` — the five anchors

```json
{ "wake": 390, "breakfast": 450, "lunch": 840, "dinner": 1200, "sleep": 1410 }
```

Minutes from midnight. Defaults if the patient skips a question ("مش متأكد"):
`wake 06:30 · breakfast 07:30 · lunch 14:00 · dinner 20:00 · sleep 23:30`.

Ramadan anchors are a second set: `suhoor`, `iftar` (sunset), `sleep`. Store both; the
active set follows `ramadan_mode`. **Nothing moves until the user taps فعّل وضع رمضان** —
so the "what will move" preview (screen 25) needs a dry-run endpoint or client-side
computation against the Ramadan anchors without committing.

### `GET/PATCH /me/scheduling-policy`

What the AI may assume when a prescription gives no time:

| Field | Values | Default |
|---|---|---|
| `ai_policy` | `ask_every_time` \| `assume_and_flag` \| `assume_silently` | `assume_and_flag` |
| `fallback_food` | `before` \| `after` \| `with` | `after` |
| `fallback_gap_minutes` | 0–120, step 15 | 30 (forced to 0 when `with`) |
| `fallback_duration` | `7_days` \| `until_pack_ends` \| `ongoing` \| `ask_doctor` | `ask_doctor` |

`assume_and_flag` is what makes screen 6 work: the row is scheduled *and* marked
low-confidence in gold until a human reviews it.

### `GET/POST/PATCH/DELETE /medicines`

```json
{
  "id": 41,
  "name": "Antodine 40 mg",
  "form": "tablet",
  "dose_text": "قرص واحد",
  "doses": [{ "anchor": "breakfast", "offset_minutes": -30 }],
  "duration": { "kind": "days", "value": 7 },
  "confidence": 0.62,
  "needs_review": true,
  "source": "ocr"
}
```

`needs_review` is what draws the gold left border and the line "مش متأكد من دي — راجعها".
Send it from the backend; don't compute a threshold in the UI.

### `GET /today`

The patient home (screen 4) and the day rail (screen 24) both read this. Return the
anchors and the doses already resolved and sorted, so the client does no scheduling maths:

```json
{
  "next": { "medicine": "Antodine 40 mg", "at": "07:00", "in_minutes": 25, "dose_id": 903 },
  "rail": [
    { "type": "anchor", "key": "wake",      "at": "06:30" },
    { "type": "dose",   "dose_id": 903, "medicine": "Antodine 40 mg",
      "at": "07:00", "rule": "الفطار − ٣٠ د", "state": "pending" },
    { "type": "anchor", "key": "breakfast", "at": "07:30" }
  ]
}
```

`state`: `pending` \| `taken` \| `skipped` \| `missed`. **Taken doses collapse to a quiet
checked line — they are never removed from the rail.**

### `POST /doses/{id}/taken` · `/snooze` · `/skip` · `/unsure`

Four actions, matching the reminder screen's four buttons (✅ تم التناول · ⏰ تأجيل ١٥ د ·
❌ تخطّي · ❓ لا أذكر). `snooze` takes `minutes`. `unsure` is **not** a skip — record it as
its own state; it exists so an elderly user is never forced to lie.

### `POST /prescriptions/scan`

Multipart image upload → returns the parsed medicines with per-row `confidence`.
The UI shows live OCR line-by-line *during* capture (screen 5); if your OCR is
server-side and can't stream, run the reveal animation client-side over the returned
lines — the design intent is "the app is reading", not a literal progress feed.

### `GET/PATCH /me/notifications`

Per-account-type groups plus the five escalation rungs, each independently switchable:

```json
{
  "groups": { "missed_dose": true, "unusual_reading": true, "circle_activity": true,
              "weekly_summary": false },
  "rungs": { "on_time": true, "plus_15": true, "plus_30": false,
             "plus_45": true, "plus_90": true },
  "quiet_hours": { "from": "23:00", "to": "06:00" }
}
```

Server-side permission rules the UI renders as 🔒:
- `missed_dose` and `emergency` — **always on, cannot be disabled by anyone.**
- For `invited` accounts, `unusual_reading`, `reports`, and `weekly_summary` are locked
  unless the care owner granted them (🔒 "مغلق").
- For `care_owner`, the `plus_45` rung is mandatory — it's the one that notifies them.
- For `self`, the `on_time` rung is mandatory.

Quiet hours silence everything **except** missed dose and emergency.

### `GET/POST /circle` · `POST /circle/invite`

Returns the invite link (`fakrny.app/join/XXXX-XXXX`) and the member list with per-member
grants. The invited member's only sign-in path is **pasting this link** — there is no email
signup for them.

### `GET /records` · `GET /archive` · `POST /export`

- Records: search across name, doctor, and date. Soft delete only — `DELETE` sets
  `deleted_at`, the row stays visible struck-through with a restore action, and purges
  after 30 days ("يُنقل إلى المحذوفات ٣٠ يومًا قبل الحذف النهائي").
- Export: takes a date range, a section include-list, and a per-section `hidden` flag, and
  returns a share link plus a PDF. The hidden flag must be enforced **server-side** — the
  recipient must not be able to read a hidden section from the payload.

### `GET /readings` · `POST /readings`

**Blood glucose only.** No blood pressure, pulse, or weight anywhere in this product.
Accepts a typed value or a voice transcript. The lab-reading screen flags values outside
*this patient's* usual range and **never returns a recommendation** — no advice, no
diagnosis, no "consider". State the number, the range, the delta, and stop. If your backend
has an LLM in this path, constrain it to that.

---

## Building the UI

### Pick the stack, then recreate — don't port

The design files are HTML prototypes. They are a **visual and behavioural specification**,
not source to copy. Rebuild them in whatever the real app uses — React Native, Flutter,
SwiftUI, Compose. The single-file structure and the `renderVals()` pattern are artefacts of
the prototype and should not appear in the product.

What must survive exactly: every hex value, every px size, every Arabic string, the
anchor model, and the 33 screens' layouts.

### Build order

1. **Tokens first.** Put the colour, type, radius, and spacing tables from `README.md` into
   the project's theme layer. Every later screen reads from it. Don't hardcode a hex twice.
2. **The ف mark** as a component with `size`, `letterColor`, `dotColor` props, plus the
   ≤16px reduced form (gold dot in two ivory rings). It's the only logo asset — there are no
   image files in this design.
3. **Primitives:** card, primary/secondary button (64px / 56px), input row, status chip,
   switch, anchor chip, bottom sheet. Board 09 of the brand file and the tokens panel at the
   end of `FAKRNY App.dc.html` show all of them together.
4. **The alert card** (screen 27) — one component rendered at five rungs × five types.
   Build it once, properly; it's used across the whole app.
5. **The scheduling core:** anchors → dose editor → today rail. This is the product. Get
   `{anchor, offset}` → resolved time → live gold preview working before anything else.
6. **Then the rest of the screens**, in the README's numbered order.

### Non-negotiables while you build

- Body text **never below 17px**; 20px minimum in patient-facing flows; dose names 24px+.
- Tap targets **56px minimum**, primary buttons **64px**.
- **Two primary actions per screen, maximum.**
- No icon-only buttons — every control carries a word.
- **Gold only** for reminders and the active state. Never for a letter, a border, a heading,
  or a chart.
- **Red only** for emergency. A missed dose is gold and neutrally worded — never red, never
  a warning triangle, never scolding language.
- No bell, pill, clock, or heart icons — the ف mark and its dot carry the identity.
- Egyptian colloquial throughout. "بتفطر الساعة كام؟" — never MSA.

### RTL

Arabic is the primary locale, not a translation layer bolted on:

- Use logical properties everywhere (`start`/`end`, not `left`/`right`). React Native and
  Flutter both handle this natively — use `I18nManager.forceRTL` / `Directionality`.
- Arabic-Indic numerals (`٠١٢٣٤٥٦٧٨٩`) in the Arabic locale, Latin in English. Times, doses,
  and readings are always tabular mono in both.
- Latin medicine names stay LTR and mono inside RTL text — `Telfast 180 mg` is never
  transliterated or reversed.
- Bundle Alexandria, IBM Plex Sans Arabic, and IBM Plex Mono with the app. Do not fetch
  fonts at runtime — this app is used on slow connections.

### Gendered copy

`sex` is not decoration. Arabic verbs and pronouns inflect, and this app speaks in second
person constantly. "بتفطر الساعة كام؟" becomes "بتفطري الساعة كام؟". Every patient-facing
string needs both forms — build the string table with a gender key from the start rather
than retrofitting it. Third-person copy in the caregiver's view inflects too
("أخد جرعته" / "أخدت جرعتها").

### Splash

The static launch image (iOS `1170×2532`, Android `1080×2400`) is the **flat `#0A4638`
ground alone** — no mark, no word. That's deliberate: it matches frame 0 of the animation
exactly, so the cut from the OS launch screen is invisible. Then the animated sequence runs
1.6s (timing table in `README.md`, board 01 of the brand file).

**Never gate the app on the splash.** If the first screen is ready in 300ms, cut. Honour
`prefers-reduced-motion` / "Reduce Motion" by showing the end state immediately.

---

## What to tell Claude Code

> I have a working backend. Build the FAKRNY frontend.
>
> Read `README.md` for the full design spec, then `INTEGRATION.md` for how it maps to my
> API. Open the HTML files in a browser as visual reference and check `screenshots/` for
> each screen's final look.
>
> Recreate these designs exactly — every colour, size, and Arabic string. Do not copy the
> HTML; rebuild in [your stack].
>
> Start with the theme tokens, the ف mark component, and the shared primitives. Then build
> the scheduling core (anchors → dose editor → today rail) before the other screens.
>
> The critical rule: a dose is `{anchor, offset}`, never a clock time. Here is my current
> schema — tell me what needs to change: [paste your schema]

Give it your API docs or an OpenAPI spec alongside. If your dose model still stores clock
times, resolve that first — every screen in this design assumes anchors.

---

## Files

| File | What it is |
|---|---|
| `README.md` | **The design spec.** Tokens, all 33 screens, the anchor model, motion timings, the do-nots. |
| `INTEGRATION.md` | This file — data model, endpoints, build order. |
| `screenshots/` | 33 PNGs, one per screen, numbered in flow order. |
| `FAKRNY App.dc.html` | The full app prototype — 33 screens, 3 account types, both languages, elder mode. Walk it with the sidebar picker. |
| `FAKRNY Prototype.html` | Same app, single self-contained file. Opens offline in any browser. |
| `FAKRNY Brand Identity.dc.html` | 8 boards: animated splash with timing table, static launch asset, app icon, reduction proof to 16px, lockups, monochrome, misuse. |
| `FAKRNY Scheduling Flow.dc.html` | The nine scheduling screens at 390×844, light and dark side by side. The most precise reference for the anchor model. |
