# Copilot rules for this repo (Bundle 264)

- Never change files in `lib/`, `android/`, `test/` or `pubspec.yaml`.
- Only fix `.github/workflows/runtime_test_264.yml`, `integration_test/rt264_*` and `tool/rt264/*`, on a new branch, and open a pull request.
- Do not push to `main`.
- The app talks to the server over HTTP only. Do not add HTTPS or certificates.
- Do not test or change video calls.
