@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0iRacing-Paint-Cleaner.ps1' -ErrorAction SilentlyContinue"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0iRacing-Paint-Cleaner.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo Launch failed. Read the error above, then press any key to close.
    pause > nul
)
