# APPLY 201 - faster friend link without the router + connection words (3.0.38+109)

Base: git 41785c1 (bundle 200). No group-chat code inside.

## Steps (PowerShell)

    cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
    git pull
    Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes201_2026-11-04.zip" .
    git add -A
    git add -f APPLY_201.md TODO_201.md
    git reset -q -- android/local.properties
    git commit -m "v3 3.0.38 bundle 201: friend link memory + deaf-tag wait + no WD re-dial + call button + connection words"
    if ($LASTEXITCODE -eq 0) { git push }
    flutter clean
    flutter pub get
    flutter build apk --release

## What changed

A1. The friend's "missing since" time is saved (setting `wd_friend_memo_201`), so opening or
    closing the app no longer restarts the 20 s wait.
A2. Search starts after the tag is published (3 s at most). After 3 search windows that heard
    no tag while phones were near, the wait is 5 s instead of 20 s. New log `WD_TAG raw`
    (first answer of a window) and `WD_SIGN deaf`.
A3. New log `WD_GROUP_LOST was=host|member p2p=on|off state=… reason=… extra=…`.
    A phone seen in the last 60 s still counts as "a phone nearby" (the group reopens sooner).
A4. A fresh peer list 1 s and 10 s into each search window (host flag seen sooner).
A5. The friend's Wi-Fi Direct address is remembered 24 h. When that address is a host, the
    app joins at once (`reason=known_host`). A wrong guess is skipped 5 min; 2 fails = forgotten.
B.  The Wi-Fi Direct member no longer dials the host again every ~5 s (link matched by the
    socket address; `MeshTransportPolicy.linksOwner`).
C.  Chats opened from a notification or after adding a friend now have the call button.
D.  Nearby: a phone with the friend's remembered Wi-Fi Direct address is not shown as "Add".
    A friend that was nearby in the last 10 min and is missing now explains one unknown
    Wi-Fi Direct phone.
E1. No error log when the server search runs with Wi-Fi off.
E2. `PRESENCE_CHANGED … why=expiry` when the status flips by time.
F.  Mock ST: "Nearby · Wi-Fi", "Nearby · Wi-Fi Direct", "Nearby · Mesh, via N phones",
    "Online", "Offline", "Connecting…" (20 s after a link drops). Chat top bar (icon + words),
    info sheet card "Connected by …", People line, call chip ("Wi-Fi Direct call" …), hold sheet,
    Chats row with no messages yet. The photo badge has one icon and colour per way (S6-S7).
    Filters and who counts as Nearby are unchanged.

No new permission, no pop-up. Router path unchanged.

## Checked here

- flutter analyze: 0 errors, no new warnings
- Kotlin compile check: clean; Link201Test: 5 passed
- Full test suite: 1205 passed, 0 failed (17 new tests; 3 old badge/menu tests updated for S6-S7)
- Phone tests (TODO_201.md section G) are the real proof.
