@echo off
setlocal EnableDelayedExpansion

echo.
echo =====================================================
echo  SLEAP Pipeline - Environment Setup (Windows)
echo  Rodrigo Garrido - Moita Lab - Champalimaud Foundation
echo =====================================================
echo.
echo  This script installs everything automatically.
echo  Nothing needs to be installed manually beforehand.
echo  First run takes about 15-25 minutes.
echo.
echo =====================================================
echo  WARNING: NVIDIA GPU
echo =====================================================
echo.
echo  NVIDIA GPU detected    : 2-10 minutes per video
echo  No GPU (CPU only)      : 1-4 HOURS per video
echo.
echo  (the pipeline works either way)
echo =====================================================
echo.
pause

:: ================================================================
:: 0. FIND OR INSTALL CONDA
:: ================================================================
echo.
echo [0/4] Checking for conda...

set "CONDA_ROOT="

:: Check common installation paths (from most to least likely)
for %%P in (
    "%UserProfile%\miniconda3"
    "%UserProfile%\Miniconda3"
    "%UserProfile%\anaconda3"
    "%UserProfile%\Anaconda3"
    "%LocalAppData%\miniconda3"
    "C:\ProgramData\miniconda3"
    "C:\ProgramData\Miniconda3"
) do (
    if exist "%%~P\Scripts\conda.exe" (
        set "CONDA_ROOT=%%~P"
        goto :conda_found
    )
)

:: Conda not found - install Miniconda automatically
echo  Conda not found. Installing Miniconda...
echo  (downloading ~90MB - please wait)
echo.

set "CONDA_ROOT=%UserProfile%\miniconda3"
set "INSTALLER=%TEMP%\miniconda_setup.exe"

:: Try downloading with curl (Windows 10+)
curl -# -L "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe" -o "!INSTALLER!" 2>nul
if not exist "!INSTALLER!" (
    echo  curl failed - trying via PowerShell...
    powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe' -OutFile '!INSTALLER!'"
)
if not exist "!INSTALLER!" (
    echo.
    echo  ERROR: Could not download Miniconda.
    echo  Check your internet connection and try again.
    pause
    exit /b 1
)

echo  Installing Miniconda to: !CONDA_ROOT!
"!INSTALLER!" /InstallationType=JustMe /RegisterPython=0 /S "/D=!CONDA_ROOT!"
del "!INSTALLER!" >nul 2>&1

if not exist "!CONDA_ROOT!\Scripts\conda.exe" (
    echo.
    echo  ERROR: Miniconda installation failed.
    pause
    exit /b 1
)
echo  OK - Miniconda installed.

:conda_found
set "CONDA_EXE=!CONDA_ROOT!\Scripts\conda.exe"
echo  OK - Conda: !CONDA_ROOT!

:: ================================================================
:: 1. INSTALL MAMBA
:: ================================================================
echo.
echo [1/4] Installing mamba (this can take a few minutes)...

"!CONDA_EXE!" install -y -n base -c conda-forge mamba

:: On Windows mamba installs as a .bat file (not .exe)
set "SOLVER=!CONDA_EXE!"
if exist "!CONDA_ROOT!\Scripts\mamba.bat" (
    set "SOLVER=!CONDA_ROOT!\Scripts\mamba.bat"
    echo  OK - mamba installed.
) else if exist "!CONDA_ROOT!\condabin\mamba.bat" (
    set "SOLVER=!CONDA_ROOT!\condabin\mamba.bat"
    echo  OK - mamba installed.
) else (
    echo  WARNING: mamba.bat not found - using conda directly.
)

:: ================================================================
:: 2. CREATE sleap_env ENVIRONMENT
:: ================================================================
echo.
echo [2/4] Creating sleap_env environment...
echo        (this can take 10-20 minutes)
echo.

"!CONDA_EXE!" env list 2>nul | findstr /C:"sleap_env" >nul
if %errorlevel%==0 (
    echo  sleap_env environment already exists - skipping.
    goto :kernel
)

"!SOLVER!" create -y -n sleap_env ^
    -c conda-forge -c nvidia -c sleap -c anaconda ^
    python=3.7 ^
    sleap=1.3.4 ^
    tensorflow=2.7.0 ^
    cudatoolkit=11.3.1 ^
    cudnn=8.2.1.32 ^
    pandas=1.3.5 ^
    scipy=1.7.3 ^
    matplotlib=3.5.3 ^
    pillow ^
    jupyterlab ^
    ipykernel

if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Failed to create environment.
    echo  Check your internet connection and try again.
    pause
    exit /b 1
)
echo.
echo  OK - sleap_env environment created.

:: Fix webcolors (newer version syntax incompatible with Python 3.7)
"!CONDA_EXE!" run -n sleap_env pip install -q "webcolors==1.11.1"

:: Reinstall Pillow via pip (wheel bundles DLLs on Windows, avoiding DLL load failures)
"!CONDA_EXE!" run -n sleap_env pip install -q --force-reinstall "pillow<10"

:: Fix requests/charset-normalizer warning
"!CONDA_EXE!" run -n sleap_env pip install -q "charset-normalizer<3"

:: ================================================================
:: 3. REGISTER JUPYTER KERNEL
:: ================================================================
:kernel
echo.
echo [3/4] Registering Jupyter kernel...

"!CONDA_EXE!" run -n sleap_env python -m ipykernel install --user --name sleap_env --display-name "Python (sleap_env)"
if %errorlevel%==0 (
    echo  OK - Kernel "Python (sleap_env)" registered.
) else (
    echo  WARNING: Kernel registration failed. Try manually afterwards:
    echo          conda activate sleap_env
    echo          python -m ipykernel install --user --name sleap_env
)

:: ================================================================
:: 4. DOWNLOAD MODEL FROM GITHUB
:: ================================================================
echo.
echo [4/4] Downloading SLEAP model (Moita Lab)...

set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"

if exist "!SCRIPT_DIR!\Sleap_Model\.git" (
    echo  Model already exists. Checking for updates...
    cd /d "!SCRIPT_DIR!\Sleap_Model"
    git pull >nul 2>&1
    cd /d "!SCRIPT_DIR!"
    echo  OK
    goto :done
)

where git >nul 2>&1
if %errorlevel%==0 (
    git clone https://github.com/moitalab/Sleap_Colab.git "!SCRIPT_DIR!\Sleap_Model"
    if %errorlevel%==0 goto :done
)

:: No git found - use PowerShell to download ZIP
echo  git not found - downloading ZIP instead...
set "MODEL_ZIP=%TEMP%\sleap_model.zip"
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest 'https://github.com/moitalab/Sleap_Colab/archive/refs/heads/main.zip' -OutFile '!MODEL_ZIP!'"
if exist "!MODEL_ZIP!" (
    powershell -NoProfile -Command "Expand-Archive -Path '!MODEL_ZIP!' -DestinationPath '!SCRIPT_DIR!' -Force"
    if exist "!SCRIPT_DIR!\Sleap_Colab-main" rename "!SCRIPT_DIR!\Sleap_Colab-main" "Sleap_Model"
    del "!MODEL_ZIP!" >nul 2>&1
    echo  OK - Model extracted.
) else (
    echo  WARNING: Could not download the model.
    echo          Download manually: https://github.com/moitalab/Sleap_Colab
    echo          and place the folder named "Sleap_Model" next to this script.
)

:done
echo.
echo =====================================================
echo  Setup complete!
echo =====================================================
echo.
echo  To get started:
echo.
echo  1. Open a new Command Prompt and run:
echo        !CONDA_ROOT!\Scripts\conda.exe run -n sleap_env jupyter lab
echo.
echo  2. Open SLEAP_Local.ipynb
echo  3. Select the "Python (sleap_env)" kernel
echo  4. Fill in the configuration cell and run the 3 steps
echo.
echo =====================================================
pause