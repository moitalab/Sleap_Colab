#Requires -Version 5.1
<#
  Abre o Jupyter Notebook com o kernel sleap_env
  Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#>

# Encontrar conda
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
    Write-Host " ERRO: Conda nao encontrado. Corre primeiro o setup_env.ps1"
    Read-Host "Prime ENTER para sair"
    exit 1
}

$envDir = "$condaRoot\envs\sleap_env"

if (-not (Test-Path "$envDir\Scripts\jupyter.exe")) {
    Write-Host " ERRO: Ambiente sleap_env nao encontrado. Corre primeiro o setup_env.ps1"
    Read-Host "Prime ENTER para sair"
    exit 1
}

# Definir PATH completo do ambiente (necessario para DLLs nativas)
$env:PATH = "$envDir;$envDir\Library\mingw-w64\bin;$envDir\Library\usr\bin;$envDir\Library\bin;$envDir\Scripts;$condaRoot\Scripts;$condaRoot;$env:PATH"
$env:CONDA_DEFAULT_ENV = "sleap_env"
$env:CONDA_PREFIX = $envDir
$env:PYTHONPATH = ""

$scriptDir = $PSScriptRoot

Write-Host ""
Write-Host " A abrir Jupyter Notebook..."
Write-Host " (o browser abre automaticamente em instantes)"
Write-Host ""

Set-Location $scriptDir
& "$envDir\Scripts\jupyter.exe" notebook --notebook-dir="$scriptDir"

Read-Host "Prime ENTER para sair"
