@echo off
chcp 65001 >nul
if "%~1"=="" goto default
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -HapPath "%~1"
goto end
:default
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
:end
pause
