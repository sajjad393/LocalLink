# APPLY 200 - phones talk without the router (3.0.35+106)

Base: git e2488b9 (199b). No group-chat changes inside.

## Steps (PowerShell)

    cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
    git pull
    Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes200_2026-11-03.zip" .
    git add -A
    git add -f APPLY_200.md TODO_200.md
    git reset -q -- android/local.properties
    git commit -m "v3 3.0.35 bundle 200: Wi-Fi Direct search window 20 s + friend backup group without router"
    if ($LASTEXITCODE -eq 0) { git push }
    flutter clean
    flutter pub get
    flutter build apk --release

## What changed

A. Search: one 20 s window, never cut by a new start; BUSY retry 3 s; NO_SERVICE_REQUESTS fix;
   cadence 25 s urgent / 30 s app open.
B. Friend backup group: name + password made from the friends' link key. Smaller id opens,
   bigger id joins (found in the Wi-Fi Direct peer list, no location permission). Stays linked.
C. Logs: WD_SEARCH, WD_PEERS, WD_TAG_FAIL, WD_SIGN, WD_FRIEND*, never a password.

No new UI, no new permission, no pop-up. Router path unchanged.

## Checked here

- flutter analyze: 0 errors
- Kotlin compile check: clean
- Full test suite: 1187 passed, 0 failed (22 new tests)
- Phone tests T1-T10 (TODO_200.md section 6) are the real proof.
