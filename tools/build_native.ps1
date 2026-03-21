param(
  [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot "native\BeamNGRaceCoachCore"
$buildDir = Join-Path $sourceDir "build"
$repoBinDir = Join-Path $repoRoot "mods\unpacked\BeamNGRaceCoach\bin"
$profileBinDir = "C:\Users\emmad\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\BeamNGRaceCoach\bin"

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
New-Item -ItemType Directory -Force -Path $repoBinDir | Out-Null

cmake -S $sourceDir -B $buildDir -G Ninja "-DCMAKE_BUILD_TYPE=$Configuration" "-DCMAKE_CXX_COMPILER=clang++"
cmake --build $buildDir

$exePath = Join-Path $buildDir "beamng_racecoach_native.exe"
if (-not (Test-Path $exePath)) {
  throw "Native executable was not built at $exePath"
}

Copy-Item -Force $exePath (Join-Path $repoBinDir "beamng_racecoach_native.exe")

if (Test-Path (Split-Path -Parent $profileBinDir)) {
  New-Item -ItemType Directory -Force -Path $profileBinDir | Out-Null
  Copy-Item -Force $exePath (Join-Path $profileBinDir "beamng_racecoach_native.exe")
}

Write-Host "Built native helper:" $exePath
