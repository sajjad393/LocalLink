# Bundle 268 (R268-1): the one release APK build command for LinkUp.
#
# The app talks to the LinkUp server over plain HTTP / ws:// ("keep http not
# https"). SecurityPolicy refuses plain HTTP in a release build unless the
# build says so on purpose with LOCLINK_ALLOW_INSECURE_HTTP=true. Without
# the flag a release APK cannot reach the server at all ("Plain HTTP is
# disabled in release builds" in the log).
#
# Risk: with plain HTTP anyone on the same Wi-Fi can read and change
# passwords, sign-in tokens, messages and files sent to the server.
#
# Run from the app folder:  powershell -ExecutionPolicy Bypass -File tool\build_release_apk.ps1
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-release.apk"
