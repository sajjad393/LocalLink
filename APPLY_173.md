# Bundle 173 - search + settings clean-up (v3.0.4+75)

Apply on top of 172 (your push d8d002f). Zip: `locallink_app_fixes173_2026-10-31.zip`.

## What changed
1. **Search in Add Contact**
   - You never show in your own search, by name or by phone number. Old copies of your own
     profile (same @username, this phone or your keys, but an old id) are hidden too.
   - Each result uses the same filled card as Nearby. It has the usual status dot on the
     photo, a line "@user · Online / Nearby / Offline", and an **Add** button.
   - People you already added show **"Added"** (and "@user · Contact"). Tapping a card still
     opens the profile.
2. **Settings -> Advanced**: the "Nearby tests" row is removed.
3. **Admin panel**: "Nearby tests (testers only)" with Link full groups and Share a LocalLink
   hotspot. They work the same as before and stay OFF.
4. **Settings -> Privacy & security** (Account screen, "Data & security"): **Extra nearby
   safety** - "Only connect nearby to contacts the app can confirm." This is the same switch
   as strict mode and stays OFF.
5. **Old unused code deleted**: the old "Nearby & Wi-Fi Direct" screen, the old radar
   animation, and the old Nearby tests screen. `nearby_devices_screen.dart` is renamed to
   `nearby_people_section.dart`.

**Not changed:** calls, video (paused), chat, the Nearby list, how the switches work.

## Files to DELETE (a zip cannot delete files)
- lib/features/connectivity/presentation/screens/wifi_direct_screen.dart
- lib/features/home/presentation/screens/nearby_experiments_screen.dart
- lib/features/directory/presentation/nearby_devices_screen.dart
- assets/animations/radar_pulse.json

## Phone test
1. Add Contact -> type your own name -> you are NOT in the list.
2. Type a friend's name -> filled card, status dot, Add. Tap Add -> name box -> "Contact added"
   -> the card shows "Added".
3. Settings -> Advanced: no "Nearby tests".
4. Admin panel -> "Nearby tests (testers only)": the 2 switches, both off.
5. Settings -> Privacy & security -> "Extra nearby safety": off.

Log (when an old copy of you was hidden): `adb logcat -s flutter | findstr DIRECTORY_SELF_HIDDEN`
The reason (username / device / key) tells us where the old copy came from.
