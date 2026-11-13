# TODO 284 - Profile photo: "Save changes" spinner never stops  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Owner (12 Nov): "When I updated profile picture the button showing continuously, not stopping until I switch screen. Check old logs."

## Log (C71 RMX5303, `uploads/LinkUp-logs-RMX5303-2026-11-12-2010.txt`)
- 19:38:05.607 `HTTP_REQUEST PUT /api/v1/profile`
- 19:38:07.170 `HTTP_RESPONSE PUT /api/v1/profile -> 200 (1562ms)`
- 19:38:10.775 `PEER_CARD_TO_FRIENDS count=0 why=photo`
- 19:38:10.786 `PROFILE_SAVED_263 synced=y`  -> the save FINISHED OK after ~5 s. Same at 19:34 (synced=y).
- So server + saving are fine; only the screen does not update.

## Cause (VERIFIED in code, de70ef7)
`lib/features/account/presentation/screens/profile_screen.dart`
- :578-580 the button reads `bloc.isSaving` directly in `build()`; nothing listens to `AccountBloc`
  (no BlocBuilder / stream listener in the screen; grep: only `setState` calls).
- Photo path `_pickImage()` (:262-266): `setState(image = picked)` then `save()` at once -> `saveProfile`
  emits `isSaving=true` before the next frame, so the rebuild shows the spinner.
- When saving ends, `isSaving=false` is emitted but `save()` (:185-219) never calls `setState` -> the
  spinner stays until something else rebuilds (switch screen, typing). Exactly what the owner sees.
- Same hidden bug the other way: tapping "Save changes" alone shows NO spinner (no rebuild at start).
- Also: `publishOwnProfile()` (~3.6 s of the 5 s) runs after `isSaving=false`, outside the spinner.

## Fix plan (smallest)
- F-1 Wrap the Save button in `BlocBuilder<AccountBloc, AccountState>` (flutter_bloc already a dependency) so it follows
  `isSaving` both ways. No other change to the save logic.
- F-2 Photo: show a small progress ring on the photo while it saves, then the new photo + "Profile saved"
  (mock-free; same look as now otherwise).
- F-3 Regression test: pick photo -> save completes -> spinner gone with no extra rebuild; and "Save changes" tap shows the
  spinner while saving.
