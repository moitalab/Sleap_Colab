#Requires -Version 5.1
<#
  SLEAP Pipeline - Setup do Ambiente (Windows)
  Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#>

Write-Host ""
Write-Host "====================================================="
Write-Host " SLEAP Pipeline - Setup do Ambiente (Windows)"
Write-Host " Rodrigo Garrido - Moita Lab - Champalimaud Foundation"
Write-Host "====================================================="
Write-Host ""
Write-Host " Este script instala tudo automaticamente."
Write-Host " Nao e necessario instalar nada manualmente."
Write-Host " Demora 15-25 minutos na primeira vez."
Write-Host ""
Write-Host "====================================================="
Write-Host " AVISO: GPU NVIDIA"
Write-Host "====================================================="
Write-Host ""
Write-Host " GPU NVIDIA detectada   : 2-10 minutos por video"
Write-Host " Sem GPU (CPU apenas)   : 1-4 HORAS por video"
Write-Host ""
Write-Host " (o pipeline funciona nos dois casos)"
Write-Host "====================================================="
Write-Host ""
Read-Host "Prime ENTER para continuar"

# ================================================================
# 0. ENCONTRAR OU INSTALAR CONDA
# ================================================================
Write-Host ""
Write-Host "[0/4] A verificar conda..."

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
    Write-Host " Conda nao encontrado. A instalar Miniconda..."
    Write-Host " (descarregar ~90MB - aguarda)"
    Write-Host ""

    $condaRoot = "$env:UserProfile\miniconda3"
    $installer = "$env:TEMP\miniconda_setup.exe"

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe' -OutFile $installer
    } catch {
        Write-Host " ERRO: Nao foi possivel descarregar o Miniconda."
        Write-Host " Verifica a ligacao a internet e tenta novamente."
        Read-Host "Prime ENTER para sair"
        exit 1
    }

    Write-Host " A instalar Miniconda em: $condaRoot"
    Start-Process -FilePath $installer -ArgumentList "/InstallationType=JustMe", "/RegisterPython=0", "/S", "/D=$condaRoot" -Wait
    Remove-Item $installer -ErrorAction SilentlyContinue

    if (-not (Test-Path "$condaRoot\Scripts\conda.exe")) {
        Write-Host ""
        Write-Host " ERRO: Instalacao do Miniconda falhou."
        Read-Host "Prime ENTER para sair"
        exit 1
    }
    Write-Host " OK - Miniconda instalado."
}

$condaExe = "$condaRoot\Scripts\conda.exe"
Write-Host " OK - Conda: $condaRoot"

# ================================================================
# 1. INSTALAR MAMBA
# ================================================================
Write-Host ""
Write-Host "[1/4] A instalar mamba (isto pode demorar alguns minutos)..."

& $condaExe install -y -n base -c conda-forge mamba

# No Windows o mamba instala como .bat (nao .exe)
$solver = $condaExe
if (Test-Path "$condaRoot\Scripts\mamba.bat") {
    $solver = "$condaRoot\Scripts\mamba.bat"
    Write-Host " OK - mamba instalado."
} elseif (Test-Path "$condaRoot\condabin\mamba.bat") {
    $solver = "$condaRoot\condabin\mamba.bat"
    Write-Host " OK - mamba instalado."
} else {
    Write-Host " AVISO: mamba.bat nao encontrado - a usar conda diretamente."
}

# ================================================================
# 2. CRIAR AMBIENTE sleap_env
# ================================================================
Write-Host ""
Write-Host "[2/4] A criar ambiente sleap_env..."
Write-Host "      (pode demorar 10-20 minutos)"
Write-Host ""

$envList = & $condaExe env list 2>$null
if ($envList -match 'sleap_env') {
    Write-Host " Ambiente sleap_env ja existe - a saltar."
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
        Write-Host " ERRO: Falhou a criacao do ambiente."
        Write-Host " Verifica a ligacao a internet e tenta novamente."
        Read-Host "Prime ENTER para sair"
        exit 1
    }
    Write-Host ""
    Write-Host " OK - Ambiente sleap_env criado."

    # Corrigir webcolors (versao nova incompativel com Python 3.7)
    & $condaExe run -n sleap_env pip install -q "webcolors==1.11.1"

    # Reinstalar Pillow via pip (wheel bundla DLLs no Windows, evita erros de DLL)
    & $condaExe run -n sleap_env pip install -q --force-reinstall "pillow<10"

    # Corrigir aviso requests/charset-normalizer
    & $condaExe run -n sleap_env pip install -q "charset-normalizer<3"
}

# ================================================================
# 3. REGISTAR KERNEL NO JUPYTER
# ================================================================
Write-Host ""
Write-Host "[3/4] A registar kernel no Jupyter..."

& $condaExe run -n sleap_env python -m ipykernel install --user --name sleap_env --display-name "Python (sleap_env)"
if ($LASTEXITCODE -eq 0) {
    Write-Host ' OK - Kernel "Python (sleap_env)" registado.'
} else {
    Write-Host " AVISO: Falhou o registo do kernel. Tenta manualmente depois:"
    Write-Host "        conda activate sleap_env"
    Write-Host "        python -m ipykernel install --user --name sleap_env"
}

# ================================================================
# 4. DESCARREGAR MODELO DO GITHUB
# ================================================================
Write-Host ""
Write-Host "[4/4] A descarregar modelo SLEAP (Moita Lab)..."

$scriptDir = $PSScriptRoot

if (Test-Path "$scriptDir\Sleap_Model\.git") {
    Write-Host " Modelo ja existe. A verificar atualizacoes..."
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
        Write-Host " git nao encontrado ou falhou - a descarregar ZIP..."
        $modelZip = "$env:TEMP\sleap_model.zip"
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest 'https://github.com/moitalab/Sleap_Colab/archive/refs/heads/main.zip' -OutFile $modelZip
            Expand-Archive -Path $modelZip -DestinationPath $scriptDir -Force
            if (Test-Path "$scriptDir\Sleap_Colab-main") {
                Rename-Item "$scriptDir\Sleap_Colab-main" "Sleap_Model"
            }
            Remove-Item $modelZip -ErrorAction SilentlyContinue
            Write-Host " OK - Modelo extraido."
        } catch {
            Write-Host " AVISO: Nao foi possivel descarregar o modelo."
            Write-Host "        Descarrega manualmente: https://github.com/moitalab/Sleap_Colab"
            Write-Host '        e coloca a pasta com o nome "Sleap_Model" ao lado deste script.'
        }
    }
}

Write-Host ""
Write-Host "====================================================="
Write-Host " Setup concluido!"
Write-Host "====================================================="
Write-Host ""
Write-Host " Para comecar:"
Write-Host ""
Write-Host " 1. Abre um novo PowerShell e corre:"
Write-Host "       $condaExe run -n sleap_env jupyter lab"
Write-Host ""
Write-Host " 2. Abre SLEAP_Local.ipynb"
Write-Host ' 3. Seleciona o kernel "Python (sleap_env)"'
Write-Host " 4. Preenche a celula de configuracao e corre os 3 passos"
Write-Host ""
Write-Host "====================================================="
Read-Host "Prime ENTER para sair"
