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

Step 4 is the one that fails silently in the real world. Say so.
Step 8 fails silently too: an unlinked or signed-out device is meant to
make zero network calls, so "nothing in Supabase" is a pass there, not a
bug — check the link state first.
