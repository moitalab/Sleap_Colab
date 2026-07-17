@echo off
setlocal EnableDelayedExpansion

echo.
echo =====================================================
echo  SLEAP Pipeline - Setup do Ambiente (Windows)
echo  Rodrigo Garrido - Moita Lab - Champalimaud Foundation
echo =====================================================
echo.
echo  Este script instala tudo automaticamente.
echo  Nao e necessario instalar nada manualmente.
echo  Demora 15-25 minutos na primeira vez.
echo.
echo =====================================================
echo  AVISO: GPU NVIDIA
echo =====================================================
echo.
echo  GPU NVIDIA detectada   : 2-10 minutos por video
echo  Sem GPU (CPU apenas)   : 1-4 HORAS por video
echo.
echo  (o pipeline funciona nos dois casos)
echo =====================================================
echo.
pause

:: ================================================================
:: 0. ENCONTRAR OU INSTALAR CONDA
:: ================================================================
echo.
echo [0/4] A verificar conda...

set "CONDA_ROOT="

:: Verificar localizacoes comuns (do mais provavel para o menos)
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

:: Conda nao encontrado - instalar Miniconda automaticamente
echo  Conda nao encontrado. A instalar Miniconda...
echo  (descarregar ~90MB - aguarda)
echo.

set "CONDA_ROOT=%UserProfile%\miniconda3"
set "INSTALLER=%TEMP%\miniconda_setup.exe"

:: Tentar descarregar com curl (Windows 10+)
curl -# -L "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe" -o "!INSTALLER!" 2>nul
if not exist "!INSTALLER!" (
    echo  curl falhou - a tentar via PowerShell...
    powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe' -OutFile '!INSTALLER!'"
)
if not exist "!INSTALLER!" (
    echo.
    echo  ERRO: Nao foi possivel descarregar o Miniconda.
    echo  Verifica a ligacao a internet e tenta novamente.
    pause
    exit /b 1
)

echo  A instalar Miniconda em: !CONDA_ROOT!
"!INSTALLER!" /InstallationType=JustMe /RegisterPython=0 /S "/D=!CONDA_ROOT!"
del "!INSTALLER!" >nul 2>&1

if not exist "!CONDA_ROOT!\Scripts\conda.exe" (
    echo.
    echo  ERRO: Instalacao do Miniconda falhou.
    pause
    exit /b 1
)
echo  OK - Miniconda instalado.

:conda_found
set "CONDA_EXE=!CONDA_ROOT!\Scripts\conda.exe"
echo  OK - Conda: !CONDA_ROOT!

:: ================================================================
:: 1. INSTALAR MAMBA
:: ================================================================
echo.
echo [1/4] A instalar mamba (isto pode demorar alguns minutos)...

"!CONDA_EXE!" install -y -n base -c conda-forge mamba

:: No Windows o mamba instala como .bat (nao .exe)
set "SOLVER=!CONDA_EXE!"
if exist "!CONDA_ROOT!\Scripts\mamba.bat" (
    set "SOLVER=!CONDA_ROOT!\Scripts\mamba.bat"
    echo  OK - mamba instalado.
) else if exist "!CONDA_ROOT!\condabin\mamba.bat" (
    set "SOLVER=!CONDA_ROOT!\condabin\mamba.bat"
    echo  OK - mamba instalado.
) else (
    echo  AVISO: mamba.bat nao encontrado - a usar conda diretamente.
)

:: ================================================================
:: 2. CRIAR AMBIENTE sleap_env
:: ================================================================
echo.
echo [2/4] A criar ambiente sleap_env...
echo       (pode demorar 10-20 minutos)
echo.

"!CONDA_EXE!" env list 2>nul | findstr /C:"sleap_env" >nul
if %errorlevel%==0 (
    echo  Ambiente sleap_env ja existe - a saltar.
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
    echo  ERRO: Falhou a criacao do ambiente.
    echo  Verifica a ligacao a internet e tenta novamente.
    pause
    exit /b 1
)
echo.
echo  OK - Ambiente sleap_env criado.

:: Corrigir webcolors (versao nova incompativel com Python 3.7)
"!CONDA_EXE!" run -n sleap_env pip install -q "webcolors==1.11.1"

:: Reinstalar Pillow via pip (wheel bundla DLLs no Windows, evita erros de DLL)
"!CONDA_EXE!" run -n sleap_env pip install -q --force-reinstall "pillow<10"

:: Corrigir aviso requests/charset-normalizer
"!CONDA_EXE!" run -n sleap_env pip install -q "charset-normalizer<3"

:: ================================================================
:: 3. REGISTAR KERNEL NO JUPYTER
:: ================================================================
:kernel
echo.
echo [3/4] A registar kernel no Jupyter...

"!CONDA_EXE!" run -n sleap_env python -m ipykernel install --user --name sleap_env --display-name "Python (sleap_env)"
if %errorlevel%==0 (
    echo  OK - Kernel "Python (sleap_env)" registado.
) else (
    echo  AVISO: Falhou o registo do kernel. Tenta manualmente depois:
    echo         conda activate sleap_env
    echo         python -m ipykernel install --user --name sleap_env
)

:: ================================================================
:: 4. DESCARREGAR MODELO DO GITHUB
:: ================================================================
echo.
echo [4/4] A descarregar modelo SLEAP (Moita Lab)...

set "SCRIPT_DIR=%~dp0"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"

if exist "!SCRIPT_DIR!\Sleap_Model\.git" (
    echo  Modelo ja existe. A verificar atualizacoes...
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

:: Sem git - usar PowerShell para descarregar ZIP
echo  git nao encontrado - a descarregar ZIP...
set "MODEL_ZIP=%TEMP%\sleap_model.zip"
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest 'https://github.com/moitalab/Sleap_Colab/archive/refs/heads/main.zip' -OutFile '!MODEL_ZIP!'"
if exist "!MODEL_ZIP!" (
    powershell -NoProfile -Command "Expand-Archive -Path '!MODEL_ZIP!' -DestinationPath '!SCRIPT_DIR!' -Force"
    if exist "!SCRIPT_DIR!\Sleap_Colab-main" rename "!SCRIPT_DIR!\Sleap_Colab-main" "Sleap_Model"
    del "!MODEL_ZIP!" >nul 2>&1
    echo  OK - Modelo extraido.
) else (
    echo  AVISO: Nao foi possivel descarregar o modelo.
    echo         Descarrega manualmente: https://github.com/moitalab/Sleap_Colab
    echo         e coloca a pasta com o nome "Sleap_Model" ao lado deste script.
)

:done
echo.
echo =====================================================
echo  Setup concluido!
echo =====================================================
echo.
echo  Para comecar:
echo.
echo  1. Abre um novo Prompt de Comando e corre:
echo        !CONDA_ROOT!\Scripts\conda.exe run -n sleap_env jupyter lab
echo.
echo  2. Abre SLEAP_Local.ipynb
echo  3. Seleciona o kernel "Python (sleap_env)"
echo  4. Preenche a celula de configuracao e corre os 3 passos
echo.
echo =====================================================
pause
