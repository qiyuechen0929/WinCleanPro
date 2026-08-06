@echo off
setlocal
title WinCleanPro Launcher

:: 透传命令行参数到 PowerShell 脚本 (如 -RunAll / -Deep)
:: 提权逻辑由 PowerShell 脚本按需处理 (最小权限原则)
set "ARGS="
:collect
if "%~1"=="" goto run
set "ARGS=%ARGS% %~1"
shift
goto collect

:run
echo Starting WinCleanPro...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinCleanPro.ps1"%ARGS%
endlocal
pause
