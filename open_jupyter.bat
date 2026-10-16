@echo off
:: Rodrigo Garrido - Moita Lab - Champalimaud Foundation
:: All the logic lives in open_jupyter.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open_jupyter.ps1" -FromBat
pause
