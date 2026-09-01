@echo off
:: Rodrigo Garrido - Moita Lab - Champalimaud Foundation
setlocal EnableDelayedExpansion

:: Find conda
set "CONDA_ROOT="
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
        goto :found
    )
)

echo  ERROR: Conda not found. Run setup_env.bat first.
pause
exit /b 1

:found
set "ENV_DIR=!CONDA_ROOT!\envs\sleap_env"

if not exist "!ENV_DIR!\Scripts\jupyter.exe" (
    echo  ERROR: sleap_env environment not found. Run setup_env.bat first.
    pause
    exit /b 1
)

:: Set environment PATH (required for native DLL resolution)
set "PATH=!ENV_DIR!;!ENV_DIR!\Library\mingw-w64\bin;!ENV_DIR!\Library\usr\bin;!ENV_DIR!\Library\bin;!ENV_DIR!\Scripts;!CONDA_ROOT!\Scripts;!CONDA_ROOT!;!PATH!"
set "CONDA_DEFAULT_ENV=sleap_env"
set "CONDA_PREFIX=!ENV_DIR!"
set "PYTHONPATH="

set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"

echo.
echo  Opening Jupyter Notebook...
echo  (the browser will open automatically in a moment)
echo.

cd /d "!SCRIPT_DIR!"
"!ENV_DIR!\Scripts\jupyter.exe" notebook --notebook-dir="!SCRIPT_DIR!"

pause