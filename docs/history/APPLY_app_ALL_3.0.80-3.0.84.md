# APPLY app ALL 3.0.80 -> 3.0.84+155 (one zip, one commit)

Contains every unpushed app change on top of 3.0.79+150 (`9d223ef`), in this order:
- 3.0.80+151: bundle 263, quiet app + key change pill.
- 3.0.81+152: bundle 265, safety fixes.
- 3.0.82+153: bundle 266, calls on every path.
- 3.0.83+154: bundle 267, Add Contact list.
- Test kit 264: GitHub runtime test + App CI.
- R268-1: release HTTP build rule.
- 3.0.84+155: bundle 269 (S-1), nearby lock can't be switched off by a fake hello.

69 files (35 new, 34 changed, none deleted).
Deploy backend 267 first (separate zip). Details per step: `docs/history/APPLY_app_3.0.80.md` ... `APPLY_app_3.0.84.md`.

Release build (always with the flag):
    flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
