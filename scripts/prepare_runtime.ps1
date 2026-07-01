$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$pcApp = Join-Path $root "pc_app"
$androidApp = Join-Path $root "android_app"
$worker = Join-Path $root "pc_worker"

function Find-Python {
    if ($env:SMART_MPC_PYTHON -and (Test-Path $env:SMART_MPC_PYTHON)) {
        return $env:SMART_MPC_PYTHON
    }

    $pythonRoot = Join-Path $env:LOCALAPPDATA "Programs\Python"
    if (Test-Path $pythonRoot) {
        $candidate = Get-ChildItem -Path $pythonRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "python.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($candidate) { return $candidate }
    }

    return "python"
}

Push-Location $pcApp
npm.cmd install
Pop-Location

Push-Location $androidApp
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
flutter pub get
Pop-Location

$python = Find-Python
& $python -m pip install -r (Join-Path $worker "requirements.txt")

Write-Host "Smart MPC runtime is prepared."
