#Requires -Version 5.1
<#
  SLEAP Pipeline - Environment Setup (Windows)
  Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#>

Write-Host ""
Write-Host "====================================================="
Write-Host " SLEAP Pipeline - Environment Setup (Windows)"
Write-Host " Rodrigo Garrido - Moita Lab - Champalimaud Foundation"
Write-Host "====================================================="
Write-Host ""
Write-Host " This script installs everything automatically."
Write-Host " Nothing needs to be installed manually beforehand."
Write-Host " First run takes about 15-25 minutes."
Write-Host ""
Write-Host "====================================================="
Write-Host " WARNING: NVIDIA GPU"
Write-Host "====================================================="
Write-Host ""
Write-Host " NVIDIA GPU detected    : 2-10 minutes per video"
Write-Host " No GPU (CPU only)      : 1-4 HOURS per video"
Write-Host ""
Write-Host " (the pipeline works either way)"
Write-Host "====================================================="
Write-Host ""
Read-Host "Press ENTER to continue"

# ================================================================
# 0. FIND OR INSTALL CONDA
# ================================================================
Write-Host ""
Write-Host "[0/4] Checking for conda..."

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
    Write-Host " Conda not found. Installing Miniconda..."
    Write-Host " (downloading ~90MB - please wait)"
    Write-Host ""

    $condaRoot = "$env:UserProfile\miniconda3"
    $installer = "$env:TEMP\miniconda_setup.exe"

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe' -OutFile $installer
    } catch {
        Write-Host " ERROR: Could not download Miniconda."
        Write-Host " Check your internet connection and try again."
        Read-Host "Press ENTER to exit"
        exit 1
    }

    Write-Host " Installing Miniconda to: $condaRoot"
    Start-Process -FilePath $installer -ArgumentList "/InstallationType=JustMe", "/RegisterPython=0", "/S", "/D=$condaRoot" -Wait
    Remove-Item $installer -ErrorAction SilentlyContinue

    if (-not (Test-Path "$condaRoot\Scripts\conda.exe")) {
        Write-Host ""
        Write-Host " ERROR: Miniconda installation failed."
        Read-Host "Press ENTER to exit"
        exit 1
    }
    Write-Host " OK - Miniconda installed."
}

$condaExe = "$condaRoot\Scripts\conda.exe"
Write-Host " OK - Conda: $condaRoot"

# ================================================================
# 1. INSTALL MAMBA
# ================================================================
Write-Host ""
Write-Host "[1/4] Installing mamba (this can take a few minutes)..."

& $condaExe install -y -n base -c conda-forge mamba

# On Windows mamba installs as a .bat file (not .exe)
$solver = $condaExe
if (Test-Path "$condaRoot\Scripts\mamba.bat") {
    $solver = "$condaRoot\Scripts\mamba.bat"
    Write-Host " OK - mamba installed."
} elseif (Test-Path "$condaRoot\condabin\mamba.bat") {
    $solver = "$condaRoot\condabin\mamba.bat"
    Write-Host " OK - mamba installed."
} else {
    Write-Host " WARNING: mamba.bat not found - using conda directly."
}

# ================================================================
# 2. CREATE sleap_env ENVIRONMENT
# ================================================================
Write-Host ""
Write-Host "[2/4] Creating sleap_env environment..."
Write-Host "      (this can take 10-20 minutes)"
Write-Host ""

$envList = & $condaExe env list 2>$null
if ($envList -match 'sleap_env') {
    Write-Host " sleap_env environment already exists - skipping."
} else {
    & $solver create -y -n sleap_env `
        -c conda-forge -c nvidia -c sleap -c anaconda `
        python=3.7 `
        sleap=1.3.4 `
        tensorflow=2.7.0 `
        cudatoolkit=11.3.1 `
        cudnn=8.2.1.32 `
        pandas=1.3.5 `
        scipy=1.7.3 `
        matplotlib=3.5.3 `
        pillow `
        jupyterlab `
        ipykernel

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host " ERROR: Failed to create environment."
        Write-Host " Check your internet connection and try again."
        Read-Host "Press ENTER to exit"
        exit 1
    }
    Write-Host ""
    Write-Host " OK - sleap_env environment created."

    $envPip = "$condaRoot\envs\sleap_env\Scripts\pip.exe"

    # Fix webcolors (newer version syntax incompatible with Python 3.7)
    & $envPip install -q "webcolors==1.11.1"

    # Reinstall Pillow via pip (wheel bundles DLLs on Windows, avoiding DLL load failures)
    & $envPip install -q --force-reinstall "pillow<10"

    # Fix requests/charset-normalizer warning
    & $envPip install -q "charset-normalizer<3"
}

# ================================================================
# 3. REGISTER JUPYTER KERNEL
# ================================================================
Write-Host ""
Write-Host "[3/4] Registering Jupyter kernel..."

& $condaExe run -n sleap_env python -m ipykernel install --user --name sleap_env --display-name "Python (sleap_env)"
if ($LASTEXITCODE -eq 0) {
    Write-Host ' OK - Kernel "Python (sleap_env)" registered.'
} else {
    Write-Host " WARNING: Kernel registration failed. Try manually afterwards:"
    Write-Host "        conda activate sleap_env"
    Write-Host "        python -m ipykernel install --user --name sleap_env"
}

# ================================================================
# 4. DOWNLOAD MODEL FROM GITHUB
# ================================================================
Write-Host ""
Write-Host "[4/4] Downloading SLEAP model (Moita Lab)..."

$scriptDir = $PSScriptRoot

if (Test-Path "$scriptDir\Sleap_Model\.git") {
    Write-Host " Model already exists. Checking for updates..."
    Push-Location "$scriptDir\Sleap_Model"
    git pull *> $null
    Pop-Location
    Write-Host " OK"
} else {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    $cloned = $false
    if ($gitCmd) {
        git clone https://github.com/moitalab/Sleap_Colab.git "$scriptDir\Sleap_Model"
        if ($LASTEXITCODE -eq 0) { $cloned = $true }
    }

    if (-not $cloned) {
        Write-Host " git not found or failed - downloading ZIP instead..."
        $modelZip = "$env:TEMP\sleap_model.zip"
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest 'https://github.com/moitalab/Sleap_Colab/archive/refs/heads/main.zip' -OutFile $modelZip
            Expand-Archive -Path $modelZip -DestinationPath $scriptDir -Force
            if (Test-Path "$scriptDir\Sleap_Colab-main") {
                Rename-Item "$scriptDir\Sleap_Colab-main" "Sleap_Model"
            }
            Remove-Item $modelZip -ErrorAction SilentlyContinue
            Write-Host " OK - Model extracted."
        } catch {
            Write-Host " WARNING: Could not download the model."
            Write-Host "          Download manually: https://github.com/moitalab/Sleap_Colab"
            Write-Host '          and place the folder named "Sleap_Model" next to this script.'
        }
    }
}

Write-Host ""
Write-Host "====================================================="
Write-Host " Setup complete!"
Write-Host "====================================================="
Write-Host ""
Write-Host " To get started:"
Write-Host ""
Write-Host " 1. Open a new PowerShell window and run:"
Write-Host "       $condaExe run -n sleap_env jupyter lab"
Write-Host ""
Write-Host " 2. Open SLEAP_Local.ipynb"
Write-Host ' 3. Select the "Python (sleap_env)" kernel'
Write-Host " 4. Fill in the configuration cell and run the 3 steps"
Write-Host ""
Write-Host "====================================================="
Read-Host "Press ENTER to exit"