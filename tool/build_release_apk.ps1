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
# Bundle 301: ARM 32 + ARM 64 only (also fixed in android/app/build.gradle).
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true --target-platform android-arm,android-arm64
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$apk = "build\app\outputs\flutter-apk\app-release.apk"
Write-Host ("APK: {0}  ({1:N1} MB)" -f $apk, ((Get-Item $apk).Length / 1MB))
