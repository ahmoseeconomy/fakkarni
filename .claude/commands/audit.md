---
description: Audit uncommitted changes against the project rules
---
Read CLAUDE.md, then review the uncommitted changes (`git diff` and
`git status`) against its rules.

Check specifically for:
- anything in `lib/domain/` importing Flutter, a database, IO or a plugin
- a resolved clock time persisted anywhere instead of anchor + offsetMinutes
- a medication auto-stopped, or a duration inferred rather than asked
- text below 17px, tap targets below 56px, primary buttons below 64px
- a hardcoded colour or size instead of `class F`
- red used for anything other than the emergency card
- gold used for anything other than a reminder or an active state
- a notification scheduled from an unconfirmed AI result
- formal MSA in any user-facing Arabic string
- `fullScreenIntent` or the `USE_EXACT_ALARM` permission

List each violation with file and line, most serious first.
Report only — do not fix anything.
