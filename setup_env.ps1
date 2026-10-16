#Requires -Version 5.1
<#
  SLEAP Pipeline - Environment Setup (Windows)
  Rodrigo Garrido - Moita Lab - Champalimaud Foundation

  Self-healing setup. Safe to re-run at any time:
    - never modifies conda's "base" environment (no mamba install)
    - uses ONLY the conda-forge / nvidia / sleap / anaconda.org channels
      (--override-channels), so the Anaconda Terms-of-Service prompt never appears
    - repairs a broken conda (libmamba solver errors) or falls back to Miniforge
    - always re-applies the pip fixes, then VALIDATES the environment by importing
      sleap / tensorflow / jupyter; if validation fails it asks whether to recreate
      the environment (or to create one with another name)
#>
param([switch]$FromBat)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$DefaultEnv   = 'sleap_env'
$KernelName   = 'sleap_env'          # kernel name used by the notebooks - always the same
$ExpectedSleap = '1.3.4'
$ExpectedTF    = '2.7.0'
$ScriptDir    = $PSScriptRoot
$EnvNameFile  = Join-Path $ScriptDir 'sleap_env_name.txt'
$ForgeRoot    = Join-Path $env:UserProfile 'miniforge3'
$ModelRepo    = 'https://github.com/moitalab/Sleap_Colab.git'

$script:CondaRoot  = $null
$script:SolverArgs = @()
$script:UsingForge = $false

# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------
function Say([string]$t) { Write-Host $t }

function Stop-Setup([string]$msg) {
    Say ""
    Say " ERROR: $msg"
    $script:Failed = $true
    throw 'SLEAP_FATAL'
}

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

function Find-CondaRoot {
    foreach ($c in (Get-CondaCandidates)) {
        if ($c -and (Test-Path "$c\Scripts\conda.exe")) { return $c }
    }
    return $null
}

function Find-EnvDir([string]$name) {
    $dirs = @()
    foreach ($c in (Get-CondaCandidates)) { if ($c) { $dirs += "$c\envs\$name" } }
    $dirs += "$env:UserProfile\.conda\envs\$name"
    foreach ($d in $dirs) { if (Test-Path "$d\python.exe") { return $d } }
    return $null
}

# Runs a program, captures stdout+stderr (no console output). Kills it after $TimeoutSec (0 = no limit).
function Invoke-Capture([string]$Exe, [string]$ArgString, [int]$TimeoutSec = 0) {
    $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $ArgString -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
        $null = $p.Handle   # keep the handle so ExitCode is available after WaitForExit
        $timedOut = $false
        if ($TimeoutSec -gt 0) {
            if (-not $p.WaitForExit($TimeoutSec * 1000)) { $timedOut = $true; try { $p.Kill() } catch {} }
        } else { $p.WaitForExit() }
        $text = "" + (Get-Content $o -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $e -Raw -ErrorAction SilentlyContinue)
        $code = if ($timedOut) { -1 } else { $p.ExitCode }
        return [pscustomobject]@{ Code = $code; Text = $text; TimedOut = $timedOut }
    } finally {
        Remove-Item $o, $e -ErrorAction SilentlyContinue
    }
}

# Windows 11 Smart App Control: 1 = on (blocks unsigned / unknown-reputation code), 2 = evaluation, 0 = off, $null = n/a
function Get-SmartAppControlState {
    try { return (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction Stop).VerifiedAndReputablePolicyState } catch { return $null }
}

function Show-SmartAppControlHelp {
    Say ""
    Say " Windows Smart App Control is ON and is blocking parts of Python/SLEAP"
    Say " (it blocks files that are not digitally signed or not known to Microsoft)."
    Say " This is a Windows security setting - this script does NOT change it."
    Say ""
    Say " Options:"
    Say "   1. Use the Google Colab notebooks on this computer (no install needed), or"
    Say "   2. Turn Smart App Control off yourself, then run this script again:"
    Say "      Settings > Privacy & security > Windows Security > App & browser control"
    Say "      > Smart App Control settings > Off"
    Say "      (it can only be turned back on by reinstalling Windows; on managed"
    Say "       computers ask your IT department first)"
    Say ""
}
function Get-CondaExe { return "$($script:CondaRoot)\Scripts\conda.exe" }

function Test-CondaHealthy {
    $bad = 'Error while loading conda entry point|CondaValueError|Traceback|non-default solver'
    foreach ($a in @('--version', 'config --show solver')) {
        $r = Invoke-Capture (Get-CondaExe) $a
        if ($r.Code -ne 0 -or $r.Text -match $bad) { return $false }
    }
    return $true
}

function Repair-Conda {
    Say " conda looks broken (solver plugin mismatch). Trying to repair it..."
    & (Get-CondaExe) update -y -n base --solver=classic --override-channels -c conda-forge `
        conda conda-libmamba-solver libmambapy | Out-Host
}

function Install-Miniforge {
    if (Test-Path "$ForgeRoot\Scripts\conda.exe") { return $true }
    Say " Installing Miniforge (conda-forge only) to: $ForgeRoot"
    $inst = Join-Path $env:TEMP 'miniforge_setup.exe'
    try {
        Invoke-WebRequest 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe' `
            -OutFile $inst -UseBasicParsing
    } catch {
        Say " Could not download Miniforge."
        return $false
    }
    Start-Process -FilePath $inst -ArgumentList '/InstallationType=JustMe', '/RegisterPython=0', '/S', "/D=$ForgeRoot" -Wait
    Remove-Item $inst -ErrorAction SilentlyContinue
    return (Test-Path "$ForgeRoot\Scripts\conda.exe")
}

function Switch-ToForge {
    if ($script:UsingForge) { return $false }
    Say ""
    Say " Falling back to a separate Miniforge install (your existing conda is left untouched)..."
    if (-not (Install-Miniforge)) { return $false }
    $script:CondaRoot  = $ForgeRoot
    $script:SolverArgs = @()
    $script:UsingForge = $true
    return $true
}

function Set-EnvPath([string]$envDir) {
    $r = $script:CondaRoot
    $env:PATH = "$envDir;$envDir\Library\mingw-w64\bin;$envDir\Library\usr\bin;$envDir\Library\bin;$envDir\Scripts;$r\Scripts;$r;$env:PATH"
    $env:CONDA_PREFIX = $envDir
    $env:PYTHONPATH = ''
    $env:PYTHONNOUSERSITE = '1'   # ignore packages in the user's roaming Python site dir
}

function New-SleapEnv([string]$name) {
    Say ""
    Say " Creating environment '$name' (this can take 10-20 minutes)..."
    $pkgs = @('python=3.7', "sleap=$ExpectedSleap", "tensorflow=$ExpectedTF", 'cudatoolkit=11.3.1',
              'cudnn=8.2.1.32', 'pandas=1.3.5', 'scipy=1.7.3', 'matplotlib=3.5.3',
              'pillow', 'jupyterlab', 'ipykernel')
    $ch = @('--override-channels', '-c', 'conda-forge', '-c', 'nvidia', '-c', 'sleap', '-c', 'anaconda')
    & (Get-CondaExe) create -y -n $name @script:SolverArgs @ch @pkgs | Out-Host
    return ($LASTEXITCODE -eq 0)
}

# Create with automatic retries: default solver -> classic solver -> Miniforge.
function Build-Env([string]$name) {
    if (New-SleapEnv $name) { return $true }
    if ($script:SolverArgs.Count -eq 0) {
        Say " Retrying with the classic solver..."
        $script:SolverArgs = @('--solver=classic')
        if (New-SleapEnv $name) { return $true }
    }
    if (Switch-ToForge) {
        if (New-SleapEnv $name) { return $true }
    }
    return $false
}

function Remove-SleapEnv([string]$name) {
    Say " Removing environment '$name'..."
    & (Get-CondaExe) env remove -y -n $name 2>$null | Out-Null
    $d = Find-EnvDir $name
    if (-not $d) { $d = "$($script:CondaRoot)\envs\$name" }
    if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
}

function Repair-EnvPackages([string]$envDir) {
    Say " Applying compatibility fixes (webcolors, pillow, charset-normalizer)..."
    Set-EnvPath $envDir
    $py = "$envDir\python.exe"
    & $py -m pip install -q --disable-pip-version-check "webcolors==1.11.1" "charset-normalizer<3" | Out-Host
    & $py -m pip install -q --disable-pip-version-check --force-reinstall "pillow<10" | Out-Host
}

function Test-Env([string]$envDir) {
    Set-EnvPath $envDir
    $code = "import PIL, webcolors, jsonschema, nbformat; import notebook.notebookapp; import tensorflow as tf; import sleap; print('SLEAP_OK', sleap.__version__, tf.__version__, len(tf.config.list_physical_devices('GPU')))"
    $r = Invoke-Capture "$envDir\python.exe" "-c `"$code`"" 240
    if ($r.TimedOut) {
        return [pscustomobject]@{ Ok = $false; Reason = "timed out after 4 minutes"; Text = $r.Text; Gpu = 0 }
    }
    $m = [regex]::Match($r.Text, 'SLEAP_OK (\S+) (\S+) (\d+)')
    if (-not $m.Success) {
        return [pscustomobject]@{ Ok = $false; Reason = "imports failed"; Text = $r.Text; Gpu = 0 }
    }
    if ($m.Groups[1].Value -ne $ExpectedSleap -or $m.Groups[2].Value -ne $ExpectedTF) {
        return [pscustomobject]@{ Ok = $false; Reason = "wrong versions (sleap $($m.Groups[1].Value), tensorflow $($m.Groups[2].Value); expected $ExpectedSleap / $ExpectedTF)"; Text = $r.Text; Gpu = 0 }
    }
    return [pscustomobject]@{ Ok = $true; Reason = ''; Text = $r.Text; Gpu = [int]$m.Groups[3].Value }
}

function Read-YesNo([string]$q) {
    while ($true) {
        $a = (Read-Host "$q [Y/N]").Trim().ToLower()
        if ($a -in @('y', 'yes', 's', 'sim')) { return $true }
        if ($a -in @('n', 'no', 'nao', 'nao')) { return $false }
    }
}

function Read-NewEnvName {
    while ($true) {
        $n = (Read-Host " New environment name (letters, numbers, - or _)").Trim()
        if ($n -notmatch '^[A-Za-z0-9_-]+$') { Say " Invalid name."; continue }
        if (Find-EnvDir $n) { Say " An environment named '$n' already exists. Choose another."; continue }
        return $n
    }
}

# Makes sure $name is a working environment. Returns the (possibly new) env name.
function Confirm-Env([string]$name) {
    $envDir = Find-EnvDir $name
    if (-not $envDir) {
        if (-not (Build-Env $name)) { Stop-Setup "Failed to create the environment. Check your internet connection and try again." }
        $envDir = Find-EnvDir $name
        if (-not $envDir) { Stop-Setup "Environment '$name' was created but could not be located." }
    } else {
        Say " Environment '$name' found: $envDir"
    }

    Repair-EnvPackages $envDir
    Say " Validating environment (imports sleap / tensorflow / jupyter - can take a minute)..."
    $v = Test-Env $envDir
    if ($v.Ok) { return @($name, $envDir, $v.Gpu) }

    Say ""
    Say " Environment '$name' is NOT working: $($v.Reason)"
    if ((Get-SmartAppControlState) -eq 1) {
        Show-SmartAppControlHelp
        Stop-Setup "Recreating the environment will not help while Smart App Control is on."
    }
    $tail = ($v.Text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 8) -join "`n"
    if ($tail) { Say " --- last output ---"; Say $tail; Say " -------------------" }
    Say ""

    if (Read-YesNo " Delete and recreate '$name'?") {
        Remove-SleapEnv $name
    } else {
        $name = Read-NewEnvName
    }
    if (-not (Build-Env $name)) { Stop-Setup "Failed to create environment '$name'." }
    $envDir = Find-EnvDir $name
    if (-not $envDir) { Stop-Setup "Environment '$name' was created but could not be located." }
    Repair-EnvPackages $envDir
    $v = Test-Env $envDir
    if (-not $v.Ok) {
        Say $v.Text
        Stop-Setup "Environment '$name' still fails validation ($($v.Reason)). Send the text above to Rodrigo."
    }
    return @($name, $envDir, $v.Gpu)
}

function Test-ModelOk {
    $f = Join-Path $ScriptDir 'Sleap_Model\best_model.h5'
    return ((Test-Path $f) -and ((Get-Item $f).Length -gt 1MB))
}

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------
try {
    Say ""
    Say "====================================================="
    Say " SLEAP Pipeline - Environment Setup (Windows)"
    Say " Rodrigo Garrido - Moita Lab - Champalimaud Foundation"
    Say "====================================================="
    Say ""
    Say " This script installs everything automatically."
    Say " Nothing needs to be installed manually beforehand."
    Say " It is safe to run again if something went wrong."
    Say " First run takes about 15-25 minutes."
    Say ""
    Say "====================================================="
    Say " WARNING: NVIDIA GPU"
    Say "====================================================="
    Say ""
    Say " NVIDIA GPU detected    : 2-10 minutes per video"
    Say " No GPU (CPU only)      : 1-4 HOURS per video"
    Say ""
    Say " (the pipeline works either way)"
    Say "====================================================="
    Say ""
    Read-Host "Press ENTER to continue" | Out-Null

    if ((Get-SmartAppControlState) -eq 1) {
        Show-SmartAppControlHelp
        if (-not (Read-YesNo " Continue anyway (it will probably fail)?")) { Stop-Setup "Stopped because Smart App Control is on." }
    }

    # ---- 0. conda ------------------------------------------------
    Say ""
    Say "[0/4] Checking for conda..."
    $script:CondaRoot = Find-CondaRoot
    if (-not $script:CondaRoot) {
        Say " Conda not found. Installing Miniconda (~90MB)..."
        $root = "$env:UserProfile\miniconda3"
        $inst = Join-Path $env:TEMP 'miniconda_setup.exe'
        $ok = $false
        try {
            Invoke-WebRequest 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe' -OutFile $inst -UseBasicParsing
            Start-Process -FilePath $inst -ArgumentList '/InstallationType=JustMe', '/RegisterPython=0', '/S', "/D=$root" -Wait
            Remove-Item $inst -ErrorAction SilentlyContinue
            $ok = Test-Path "$root\Scripts\conda.exe"
        } catch {}
        if ($ok) {
            $script:CondaRoot = $root
            Say " OK - Miniconda installed."
        } elseif (-not (Switch-ToForge)) {
            Stop-Setup "Could not install conda. Check your internet connection and try again."
        }
    }
    Say " Conda: $($script:CondaRoot)"
    if ($script:CondaRoot -eq $ForgeRoot) { $script:UsingForge = $true }

    # ---- 1. conda health ----------------------------------------
    Say ""
    Say "[1/4] Checking that conda works..."
    if (Test-CondaHealthy) {
        Say " OK"
    } else {
        Repair-Conda
        if (Test-CondaHealthy) {
            Say " OK - conda repaired."
        } else {
            Say " Could not repair conda."
            if (-not (Switch-ToForge)) { Stop-Setup "conda is unusable and Miniforge could not be installed." }
        }
    }

    # ---- 2. environment -----------------------------------------
    Say ""
    Say "[2/4] Preparing the SLEAP environment..."
    $envName = $DefaultEnv
    if (Test-Path $EnvNameFile) {
        $saved = (Get-Content $EnvNameFile -Raw).Trim()
        if ($saved -match '^[A-Za-z0-9_-]+$') { $envName = $saved }
    }
    $res = Confirm-Env $envName
    $envName = $res[0]; $envDir = $res[1]; $gpu = $res[2]
    Set-Content -Path $EnvNameFile -Value $envName -Encoding ASCII
    Say " OK - environment '$envName' works (SLEAP $ExpectedSleap, TensorFlow $ExpectedTF)."
    if ($gpu -gt 0) { Say " GPU detected: $gpu device(s) - fast mode." } else { Say " No GPU detected - CPU mode (slow but works)." }

    # ---- 3. kernel ----------------------------------------------
    Say ""
    Say "[3/4] Registering Jupyter kernel..."
    Set-EnvPath $envDir
    & "$envDir\python.exe" -m ipykernel install --user --name $KernelName --display-name "Python (sleap_env)"
    if ($LASTEXITCODE -eq 0) {
        Say ' OK - Kernel "Python (sleap_env)" registered.'
    } else {
        Say " WARNING: Kernel registration failed. Run setup_env.bat again."
    }

    # ---- 4. model -----------------------------------------------
    Say ""
    Say "[4/4] Downloading SLEAP model (Moita Lab)..."
    $modelDir = Join-Path $ScriptDir 'Sleap_Model'
    $git = Get-Command git -ErrorAction SilentlyContinue

    if (Test-Path "$modelDir\.git") {
        Say " Model already exists. Checking for updates..."
        if ($git) { Push-Location $modelDir; git pull *> $null; Pop-Location }
    } elseif (-not (Test-Path $modelDir) -or -not (Get-ChildItem $modelDir -ErrorAction SilentlyContinue)) {
        $cloned = $false
        if ($git) {
            git clone $ModelRepo $modelDir
            if ($LASTEXITCODE -eq 0) { $cloned = $true }
        }
        if (-not $cloned) {
            Say " git not found or failed - downloading ZIP instead..."
            $zip = Join-Path $env:TEMP 'sleap_model.zip'
            try {
                Invoke-WebRequest 'https://github.com/moitalab/Sleap_Colab/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
                Expand-Archive -Path $zip -DestinationPath $ScriptDir -Force
                if (Test-Path "$ScriptDir\Sleap_Colab-main") { Rename-Item "$ScriptDir\Sleap_Colab-main" 'Sleap_Model' }
                Remove-Item $zip -ErrorAction SilentlyContinue
            } catch {
                Say " WARNING: Could not download the model ZIP."
            }
        }
    }

    # best_model.h5 is stored with Git LFS: without git-lfs (or via ZIP) only a tiny pointer file arrives.
    if (-not (Test-ModelOk)) {
        if ($git -and (Test-Path "$modelDir\.git")) {
            Say " Fetching model weights via Git LFS..."
            Push-Location $modelDir; git lfs install *> $null; git lfs pull *> $null; Pop-Location
        }
    }
    if (-not (Test-ModelOk)) {
        Say " Downloading model weights directly from GitHub..."
        try {
            New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
            foreach ($f in @('best_model.h5', 'training_config.json')) {
                Invoke-WebRequest "https://github.com/moitalab/Sleap_Colab/raw/main/$f" -OutFile (Join-Path $modelDir $f) -UseBasicParsing
            }
        } catch {
            Say " WARNING: direct download failed."
        }
    }
    if (Test-ModelOk) {
        Say " OK - model ready."
    } else {
        Say " WARNING: best_model.h5 is missing or incomplete."
        Say "          Download manually: https://github.com/moitalab/Sleap_Colab"
        Say '          and place the folder named "Sleap_Model" next to this script.'
    }

    Say ""
    Say "====================================================="
    Say " Setup complete"
    Say "====================================================="
    Say ""
    Say " To get started:"
    Say ""
    Say " 1. Double-click open_jupyter.bat"
    Say " 2. Open SLEAP_Local.ipynb"
    Say ' 3. Select the "Python (sleap_env)" kernel'
    Say " 4. Fill in the configuration cell and run the 3 steps"
    Say ""
    Say "====================================================="
}
catch {
    if ($_.Exception.Message -ne 'SLEAP_FATAL') {
        Say ""
        Say " UNEXPECTED ERROR: $($_.Exception.Message)"
        $script:Failed = $true
    }
}
finally {
    if (-not $FromBat) { Read-Host "Press ENTER to exit" | Out-Null }
}
if ($script:Failed) { exit 1 }
