@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build.ps1" -Action studio
if errorlevel 1 (
    echo.
    echo Pantry Logic could not be opened. Review the error above.
    pause
    exit /b 1
)
