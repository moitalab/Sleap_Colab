#Requires -Version 5.1
<#
  Launches Jupyter Notebook using the sleap_env kernel
  Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#>

# Locate conda
$condaRoot = $null
$candidates = @(
    "$env:UserProfile\miniconda3",
    "$env:UserProfile\Miniconda3",
    "$env:UserProfile\anaconda3",
    "$env:UserProfile\Anaconda3",
    "$env:LocalAppData\miniconda3",
    "C:\ProgramData\miniconda3",
    "C:\ProgramData\Miniconda3"
)
foreach ($candidate in $candidates) {
    if (Test-Path "$candidate\Scripts\conda.exe") {
        $condaRoot = $candidate
        break
    }
}

if (-not $condaRoot) {
    Write-Host " ERROR: Conda not found. Run setup_env.ps1 first."
    Read-Host "Press ENTER to exit"
    exit 1
}

$envDir = "$condaRoot\envs\sleap_env"

if (-not (Test-Path "$envDir\Scripts\jupyter.exe")) {
    Write-Host " ERROR: sleap_env environment not found. Run setup_env.ps1 first."
    Read-Host "Press ENTER to exit"
    exit 1
}

# Set environment PATH (required for native DLL resolution)
$env:PATH = "$envDir;$envDir\Library\mingw-w64\bin;$envDir\Library\usr\bin;$envDir\Library\bin;$envDir\Scripts;$condaRoot\Scripts;$condaRoot;$env:PATH"
$env:CONDA_DEFAULT_ENV = "sleap_env"
$env:CONDA_PREFIX = $envDir
$env:PYTHONPATH = ""

$scriptDir = $PSScriptRoot

Write-Host ""
Write-Host " Launching Jupyter Notebook..."
Write-Host " (the browser will open automatically in a moment)"
Write-Host ""

Set-Location $scriptDir
& "$envDir\Scripts\jupyter.exe" notebook --notebook-dir="$scriptDir"

Read-Host "Press ENTER to exit"