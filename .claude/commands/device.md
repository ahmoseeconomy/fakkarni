---
description: The manual real-device checklist for notifications
---
Print the manual notification checklist for a real device, then wait.
I run these by hand on the phone — do not execute anything.

Cover, in order, and for each one say what a pass looks like and what the
most likely cause of a failure is:

1. Notification permission granted (Android 13+).
2. Exact alarm permission — what `canScheduleExact()` returns, and how to
   grant it in system settings when it is denied.
3. Schedule a dose 2 minutes out, swipe the app away from recents, wait.
4. Exempt the app from battery optimisation, then repeat step 3.
5. Reboot the phone and confirm the pending reminders survived.
6. Change the wake or breakfast time and confirm every dependent dose moved
   with it.
7. Escalation ladder (4.1): a dose two minutes out, phone locked and
   untouched — rings at +0, +15 with vibration, +30. Then repeat and tap
   «أخدته» on the +15 notification: the +30 rung must never ring. Then
   repeat and touch nothing: past +45, «يومك» shows «نسيتها؟».
8. Background sync (4.2a): force-quit the app, tap «أخدته» on the lock
   screen, and check Supabase shows that dose_events row as `state=taken`
   within a minute — without the app ever appearing on screen. Then leave
   a dose past 45 minutes and interact with any notification: the cloud
   row shows `missed`.

9. Contact picker (round 23), on **both** phones — none of this has ever
   run on hardware, and both halves below are read from the plugin's
   source, not observed:
   a. iOS: «معلومات الطوارئ» → «عدّل» → «من جهات الاتصال». A pass is the
      system sheet appearing **with no permission prompt at all** —
      `CNContactPickerViewController` runs outside our process, so iOS
      should never ask. If a prompt appears, something is reading the
      address book rather than picking from it; stop and say so, because
      that is the rule this feature rests on, not a cosmetic difference.
      Then pick a contact with more than one number: it must ask which
      number, and fill name + that number, leaving «صلة القرابة» empty.
   b. Android: the same path, then the case with **no picker available** —
      a device or profile with no contacts app, or the picker disabled.
      The expected behaviour is `ContactPickerDenied` → the one line
      «الموبايل ما سمحش لنا نفتح جهات الاتصال…», the «من جهات الاتصال»
      button gone, and manual entry still working. **This mapping is a
      guess from the plugin's Kotlin** (`ACTION_PICK` with no resolver);
      it may instead return null, which would look like a plain cancel —
      silent, no line, button still there. Report which one actually
      happens, because the wording depends on it.
   c. Either phone: confirm nothing else changed — the app must still ask
      for no contacts permission anywhere in system settings.

0. **Before any round that touches the cloud — paste
   `supabase/verify_migrations.sql` into the SQL editor.** It is read-only
   (one SELECT; no DDL, no writes) and returns one row per migration
   0001-0017 with `expected` / `found` / `ok` / `missing`. Everything must
   be ok; anything else names the object that is absent.
   Say this out loud when reporting: **`0014` had never been run on the
   live project, and finding that cost an hour** — a caregiver screen that
   would not load, a column audit that came back clean because it was
   reading the repo rather than the database, and a debug log added just to
   see the real error. This script answers the same question in one paste.
   Run it **before** the steps below, not after: the rest of this checklist
   assumes the schema is what the code expects.

Step 4 is the one that fails silently in the real world. Say so.
Step 8 fails silently too: an unlinked or signed-out device is meant to
make zero network calls, so "nothing in Supabase" is a pass there, not a
bug — check the link state first.
