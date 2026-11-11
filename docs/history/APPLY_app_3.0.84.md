# APPLY app 3.0.84+155 - bundle 269 (S-1): nearby lock can't be switched off by a fake hello

Zip: `locallink_app_3.0.84_2026-11-14.zip`. Apply on top of R268-1 (zip `locallink_app_r268-1_2026-11-14.zip` first).

## What it fixes
- A phone nearby could claim to be your friend and say "my app can't lock messages" when it connected. Your phone believed it, remembered it, and sent that friend's chats unlocked (plain) until the real friend sent a locked message again.
- Now, once your phone has opened a locked message from that friend with the friend's own key, a hello that says "can't lock" is ignored (log `SEAL_DOWNGRADE_IGNORED`). The proof is remembered after a restart.
- A friend on a really old app (known only from its hello) still gets plain messages, as before.

## Not changed (known limits)
- A plain message that claims to be from a friend is still shown (dropping it could lose messages from friends on old apps).
- "Strict link check" stays off.
- No native, server or screen change.
- Friends are protected after their first locked message arrives on 3.0.84.

## Release build (same rule as R268-1)
```powershell
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
```

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.84_2026-11-14.zip" .
git add -A
git add -f docs/history/APPLY_app_3.0.84.md docs/history/TODO_269.md
git commit -m "v3 3.0.84+155 bundle 269: a nearby hello that says the friend can't lock messages no longer switches a proven friend to plain - proof is a locked message opened with the friend's own key (saved as seal_proven_peers_v1, kept after restart, stranger/group locks don't count), the ignored hello is logged SEAL_DOWNGRADE_IGNORED with a short id, friends known only from hellos (old apps) still get plain as before"
```

## Files
- `lib/features/connectivity/data/services/sealing_peer_transport.dart`: the guard + the saved proof.
- `test/seal_downgrade_269_test.dart`: new, 6 tests.
- Version: `lib/core/config/app_build.dart`, `pubspec.yaml`, `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`.
- `docs/history/APPLY_app_3.0.84.md`, `docs/history/TODO_269.md`.

## Phone check
Chat with a friend nearby (Wi-Fi Direct or the same Wi-Fi) for one message each way. It must still work. The log must show no `SEAL_DOWNGRADE_IGNORED` for a real friend; it appears only when a fake "can't lock" hello arrives.
