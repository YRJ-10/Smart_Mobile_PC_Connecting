$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location (Join-Path $root "android_app")
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
flutter run
Pop-Location
