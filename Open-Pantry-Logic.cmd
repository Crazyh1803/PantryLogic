@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Open-PantryLogic.ps1"
if errorlevel 1 (
    echo.
    echo Pantry Logic could not be opened. Review the error above.
    echo Launch log: %TEMP%\PantryLogic-launch.log
    pause
    exit /b 1
)
