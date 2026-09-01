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

Step 4 is the one that fails silently in the real world. Say so.
