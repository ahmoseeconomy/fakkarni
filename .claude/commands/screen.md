---
description: Build one screen from its mockup, with the rules enforced
---
Build the screen named in $ARGUMENTS.

1. Look at its mockup in `screenshots/` before writing anything.
2. Match its layout, hierarchy and spacing.
3. Take every colour and size from `class F` in `lib/core/theme/tokens.dart`.
   Never measure a value off the image.
4. Where the mockup is tighter than the minimums in CLAUDE.md (17px text,
   56px targets, 64px primary buttons), follow the minimums — then tell me
   exactly which parts you changed and why.
5. Use the Arabic strings from the mockup verbatim. Do not rewrite them and do
   not turn them into formal MSA.
6. No icon-only controls. Every control carries a word.

Build it with mock data only. Do not wire it to the database or to
notifications unless I say so.

Then run `flutter analyze` and tell me what to look at on screen.
