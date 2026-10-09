@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
if errorlevel 1 goto end
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
:end
pause
