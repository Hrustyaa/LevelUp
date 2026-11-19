# Run from the Flutter project root AFTER copying the files from this kit.
$ErrorActionPreference = 'Stop'
$gradle = Join-Path $PWD 'android/app/build.gradle.kts'
if (!(Test-Path $gradle)) { throw "No android/app/build.gradle.kts found. Run 'flutter create --org com.levelup --platforms=android levelup_test' first." }
$content = Get-Content $gradle -Raw
$content = $content -replace 'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36'
$content = $content -replace 'targetSdk\s*=\s*flutter\.targetSdkVersion', 'targetSdk = 36'
$content = $content -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
[System.IO.File]::WriteAllText($gradle, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Android SDK settings updated: compileSdk=36, targetSdk=36, minSdk=24'
flutter pub get
Write-Host 'Next: flutter doctor --android-licenses ; flutter devices ; flutter run'
