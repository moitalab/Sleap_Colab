#Requires -Version 5.1
<#
  Launches Jupyter Notebook using the sleap_env kernel
  Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#>
param([switch]$FromBat)

$ErrorActionPreference = 'Continue'
$ScriptDir   = $PSScriptRoot
$EnvNameFile = Join-Path $ScriptDir 'sleap_env_name.txt'

function Get-CondaCandidates {
    $c = @()
    if ($env:CONDA_EXE) { $c += (Split-Path (Split-Path $env:CONDA_EXE -Parent) -Parent) }
    $cmd = Get-Command conda -ErrorAction SilentlyContinue
    if ($cmd) { $c += (Split-Path (Split-Path $cmd.Source -Parent) -Parent) }
    $c += @(
        "$env:UserProfile\miniconda3", "$env:UserProfile\Miniconda3",
        "$env:UserProfile\anaconda3",  "$env:UserProfile\Anaconda3",
        "$env:UserProfile\miniforge3", "$env:UserProfile\mambaforge",
        "$env:LocalAppData\miniconda3", "$env:LocalAppData\anaconda3",
        "C:\ProgramData\miniconda3", "C:\ProgramData\Miniconda3",
        "C:\ProgramData\anaconda3",  "C:\ProgramData\Anaconda3"
    )
    return $c
}

function Stop-Launch([string]$msg) {
    Write-Host ""
    Write-Host " ERROR: $msg"
    Write-Host ""
    $script:Failed = $true
    throw 'SLEAP_FATAL'
}

try {
    # Environment name (setup_env may have created it under another name)
    $envName = 'sleap_env'
    if (Test-Path $EnvNameFile) {
        $saved = (Get-Content $EnvNameFile -Raw).Trim()
        if ($saved -match '^[A-Za-z0-9_-]+$') { $envName = $saved }
    }

    # Locate the environment (and the conda that owns it)
    $envDir = $null; $condaRoot = $null
    $dirs = @()
    foreach ($c in (Get-CondaCandidates)) { if ($c) { $dirs += @{ Root = $c; Env = "$c\envs\$envName" } } }
    $dirs += @{ Root = $null; Env = "$env:UserProfile\.conda\envs\$envName" }
    foreach ($d in $dirs) {
        if (Test-Path "$($d.Env)\Scripts\jupyter.exe") { $envDir = $d.Env; $condaRoot = $d.Root; break }
    }
    if (-not $envDir) { Stop-Launch "Environment '$envName' not found. Run setup_env.bat first." }
    if (-not $condaRoot) { $condaRoot = Split-Path (Split-Path $envDir -Parent) -Parent }

    # Environment PATH (required for native DLL resolution)
    $env:PATH = "$envDir;$envDir\Library\mingw-w64\bin;$envDir\Library\usr\bin;$envDir\Library\bin;$envDir\Scripts;$condaRoot\Scripts;$condaRoot;$env:PATH"
    $env:CONDA_DEFAULT_ENV = $envName
    $env:CONDA_PREFIX = $envDir
    $env:PYTHONPATH = ''
    $env:PYTHONNOUSERSITE = '1'

    # Quick health check so the user gets a clear message instead of a Python traceback
    $tmpO = [IO.Path]::GetTempFileName(); $tmpE = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath "$envDir\python.exe" `
            -ArgumentList '-c', '"import PIL, webcolors, nbformat, notebook.notebookapp"' `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmpO -RedirectStandardError $tmpE
    $errText = Get-Content $tmpE -Raw -ErrorAction SilentlyContinue
    Remove-Item $tmpO, $tmpE -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) {
        Write-Host $errText
        $sac = $null
        try { $sac = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction Stop).VerifiedAndReputablePolicyState } catch {}
        if ($sac -eq 1) {
            Write-Host " Windows Smart App Control is ON and is probably blocking Python files."
            Write-Host " Turn it off (Settings > Privacy & security > Windows Security > App & browser control"
            Write-Host " > Smart App Control settings) or use the Google Colab notebooks instead."
            Write-Host ""
        }
        Stop-Launch "The SLEAP environment is broken. Run setup_env.bat - it repairs it automatically."
    }

    Write-Host ""
    Write-Host " Launching Jupyter Notebook..."
    Write-Host " (the browser will open automatically in a moment)"
    Write-Host ""

    Set-Location $ScriptDir
    & "$envDir\Scripts\jupyter.exe" notebook --notebook-dir="$ScriptDir"
}
catch {
    if ($_.Exception.Message -ne 'SLEAP_FATAL') {
        Write-Host " UNEXPECTED ERROR: $($_.Exception.Message)"
        $script:Failed = $true
    }
}
finally {
    if (-not $FromBat) { Read-Host "Press ENTER to exit" | Out-Null }
}
if ($script:Failed) { exit 1 }
