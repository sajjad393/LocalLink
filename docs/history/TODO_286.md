# TODO 286 - Recovery code: no banner after sign-up, hard to find  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Owner (12 Nov): "I have created many accounts but didn't see any recovery code banner on home. Check the logs. Also in profile settings I did not find it."

## Logs (12 Nov) - 4 new accounts, none showed a code
| Phone | Time | Log line |
|---|---|---|
| C71 RMX5303 | 19:33:54 | `AUTH_RESULT what=create mode=server` |
| Note RMX3938 | 19:35:44 | `AUTH_RESULT what=create mode=server` |
| ZTE Z2453 | 19:41:01 | `AUTH_RESULT what=create mode=offline reason=no_server` |
| TECNO BG6 | 19:53:04 | `AUTH_RESULT what=create mode=offline reason=no_server` |
No recovery-code screen/card event after any of them (there is no log for it either).

## Cause (VERIFIED in code, de70ef7)
1. No banner by design: `setup_screen.dart:148` "Bundle 110: no recovery-code dialog at account creation - the code stays reachable
   from Profile -> Recovery code". After sign-up only the Profile screen opens.
2. The only home card is `JoinCard218.recovery` "Your recovery code changed" (`home_screen.dart:379/511`) - it shows ONLY when an
   offline account is published and the server CHANGED the code. Never for a normal new account.
3. Settings > Account (`account_center_screen.dart:322-345`): "Keep your recovery code private" is a plain NOTE, not tappable.
4. The real row is hidden: Settings > Account > "Tap to edit name and photo" > scroll to the very bottom > Account > Recovery code
   (`profile_screen.dart:612-619`).
5. Even there it never SHOWS the code: dialog says "A recovery code is already configured. Generate a new one to replace it."
   (`profile_screen.dart:276-300`). The code is kept on the phone (`store.localRecoveryCode`).

## Fix plan
- R-1 Home card after a new account (server or offline): "Save your recovery code" + the code box (Show / Copy) +
  "Save on WhatsApp" (reuse `RecoveryCodeBox235`, `SaveOnWhatsApp235`). Stays until saved; "Later" hides it for 1 day.
- R-2 Settings > Account > Backup and safety: real row "Recovery code" (replaces the note) -> screen: code hidden,
  Show / Copy / Save on WhatsApp, "Make a new code".
- R-3 Profile page: the old "Recovery code" row opens the same screen (no duplicate logic).
- **Owner choices (12 Nov):**
  - Q1 = card for NEW and EXISTING accounts: shown until "Saved" is tapped (flag `recovery_saved_286` on the phone).
    An old account with no code on the phone -> the card offers "Make a new code" instead.
  - Q2 = ask the password before showing the code (R-2/R-3 screen). Check with the saved offline hash
    (same check as offline sign-in), so it works with no server. Wrong password -> "Wrong password", code stays hidden.
  - R-1 home card right after sign-up shows the code without a password (the user just typed it).
- Logs: `RECOVERY_CARD shown/saved/later`, `RECOVERY_VIEW` (never the code itself).

## Mock (13 Nov) - `mocks/recovery_code_286.html` + `_light.html`, made by `mocks/m286/make.py`
- Home is drawn like the app today (bg #121318, cards #1a1b20, nav pill #2d334b sampled from screenshots; layout from
  `home_screen.dart _chatsTab`: TabTopBar Chats + search, join cards, MyLinksCard273, CONVERSATIONS group, FAB, nav). Only the card is new.
- Card place: inside `_joinCards218()` (top of Chats, above My links). One card at a time; AdminBlocked / SessionDead first.
- States: new account (code box hidden, Show/Copy, Save on WhatsApp, I saved it / Later; NO x button, owner 13 Nov "cross button not looks good"); existing (Show my code + Later);
  no code (Make my code + Later); saved (card slides away + "Recovery code saved").
- Settings > Account: first row in "Backup and safety" "Recovery code" + tag Not saved (orange) / Saved (green); the old
  `account_recovery_note` (account_center_screen.dart:322-345) is removed.
- Password screen (offline hash check), wrong password red line; code screen: big code, Hide/Copy, Save on WhatsApp, 2 tips,
  "Make a new code" (confirm "Your old code stops working").
- APPROVED 13 Nov ("Perfect mock"). Toast look -> TODO 289.
