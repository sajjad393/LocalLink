# APPLY app 3.0.83+154 (TODO 267)

Zip: `locallink_app_3.0.83_2026-11-14.zip`, on top of 3.0.82+153.
Backend: deploy `locallink_backend_267_2026-11-13.zip` FIRST (see `APPLY_backend_267.md`). With an older server the list shows only the people your nearby phones know.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.83_2026-11-14.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_267.md docs/history/APPLY_app_3.0.83.md
git commit -m "v3 3.0.83+154 bundle 267: Add Contact shows people you can add while the search box is empty - everyone on the server who is not in your contacts, or with no server the people your nearby phones know; Nearby is hidden and starts only when a search finds no one, with the search animation and Please wait a few seconds"
git push
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
```
IMPORTANT: keep `--dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` on the build line. Without it a release APK refuses plain HTTP, and since 3.0.79 (HTTP only) it can't reach the server at all (see the regression report, bug R268-1).

## What changes (Add Contact)
- Empty search box: "People you can add" = everyone on the server who is not in your contacts (50 at a time, more when you scroll). With no server: "People nearby phones know".
- Nothing to show: "Everyone is already in your contacts." / "No one to show yet. Search a name or scan a QR code."
- Nearby is hidden. It starts only when a search finds no one: "No one called .. found." + the search animation + "Please wait a few seconds".
- Log `ADD_LIST_267 src=server|nearby shown=N more=y|n ms=..` (no names).

## Old tests changed
- `test/bundle170_test.dart`: the empty-box text is now "No one to show yet. Search a name or scan a QR code." (was "Type at least 2 characters to search.").
- The version lines in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart`.

## Tests
- New `test/bundle267_test.dart`: 12 tests, pass. Backend: `go vet` + `go test` pass.
- Full Flutter suite on this tree: 2695 tests, all pass (11 chunks); Kotlin 470 tests pass; flutter analyze 0 errors (the same 9 old warnings).
