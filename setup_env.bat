@echo off
:: SLEAP Pipeline - Environment Setup (Windows)
:: Rodrigo Garrido - Moita Lab - Champalimaud Foundation
:: All the logic lives in setup_env.ps1 (same behaviour from double-click, CMD or Anaconda Prompt).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_env.ps1" -FromBat
pause
