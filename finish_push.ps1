# finish_push.ps1 - run from the ROOT of your LocalLink repo (folder with pubspec.yaml)
# Finishes the update: deletes 9 files that should be gone, adds the 2 reports,
# commits, and pushes. Safe to re-run.
$ErrorActionPreference = "Continue"

$toDelete = @(
  "android/app/src/main/kotlin/com/sajjad/locallink/DirectFileSecurity.kt",
  "android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshPacketAuthentication.kt",
  "android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshRouteAdvertisementAuthenticator.kt",
  "android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshTransportSessionKeyPolicy.kt",
  "android/app/src/test/kotlin/com/sajjad/locallink/DirectFileSecurityTest.kt",
  "android/app/src/test/kotlin/com/sajjad/locallink/mesh/MeshPacketAuthenticationTest.kt",
  "android/app/src/test/kotlin/com/sajjad/locallink/mesh/MeshRouteAdvertisementAuthenticatorTest.kt",
  "android/app/src/test/kotlin/com/sajjad/locallink/mesh/MeshTransportSessionKeyPolicyTest.kt",
  "android/local.properties"
)

Write-Host "== Deleting orphaned / machine-specific files =="
foreach ($f in $toDelete) {
  if (Test-Path $f) {
    git rm -f --quiet $f
    Write-Host "  removed   $f"
  } else {
    Write-Host "  already gone: $f"
  }
}

Write-Host "== Adding reports =="
if (Test-Path "AUDIT_REPORT.md")   { git add -f AUDIT_REPORT.md;   Write-Host "  staged AUDIT_REPORT.md" }
if (Test-Path "TESTING_REPORT.md") { git add -f TESTING_REPORT.md; Write-Host "  staged TESTING_REPORT.md" }

git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git commit -m "Add audit + testing reports; finish E2E crypto removal (delete orphaned native files)"
  Write-Host "== Pushing =="
  git push origin main
  Write-Host "DONE. Verify: git log --oneline -2"
} else {
  Write-Host "Nothing staged - repo may already be finished."
  git status --short
  git log --oneline -3
}
