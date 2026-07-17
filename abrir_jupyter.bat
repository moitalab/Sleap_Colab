@echo off
:: Rodrigo Garrido - Moita Lab - Champalimaud Foundation
setlocal EnableDelayedExpansion

:: Encontrar conda
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

echo  ERRO: Conda nao encontrado. Corre primeiro o setup_env.bat
pause
exit /b 1

:found
set "ENV_DIR=!CONDA_ROOT!\envs\sleap_env"

if not exist "!ENV_DIR!\Scripts\jupyter.exe" (
    echo  ERRO: Ambiente sleap_env nao encontrado. Corre primeiro o setup_env.bat
    pause
    exit /b 1
)

:: Definir PATH completo do ambiente (necessario para DLLs nativas)
set "PATH=!ENV_DIR!;!ENV_DIR!\Library\mingw-w64\bin;!ENV_DIR!\Library\usr\bin;!ENV_DIR!\Library\bin;!ENV_DIR!\Scripts;!CONDA_ROOT!\Scripts;!CONDA_ROOT!;!PATH!"
set "CONDA_DEFAULT_ENV=sleap_env"
set "CONDA_PREFIX=!ENV_DIR!"
set "PYTHONPATH="

set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"

echo.
echo  A abrir Jupyter Notebook...
echo  (o browser abre automaticamente em instantes)
echo.

cd /d "!SCRIPT_DIR!"
"!ENV_DIR!\Scripts\jupyter.exe" notebook --notebook-dir="!SCRIPT_DIR!"

pause
