$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$workerDir = Join-Path $root "pc_worker"
$distDir = Join-Path $workerDir "dist"
$buildDir = Join-Path $workerDir "build"

function Find-Python {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return $py.Source
    }

    throw "Python was not found. Install Python, then run this script again."
}

$python = Find-Python
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

& $python -m PyInstaller --clean --noconfirm --onefile `
    --distpath $distDir `
    --workpath $buildDir `
    --specpath $buildDir `
    --name smart-mpc-worker `
    (Join-Path $workerDir "worker.py")

& $python -m PyInstaller --clean --noconfirm --onefile `
    --distpath $distDir `
    --workpath $buildDir `
    --specpath $buildDir `
    --name smart-mpc-screen-streamer `
    (Join-Path $workerDir "screen_streamer.py")
