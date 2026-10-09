@echo off
title SafeChat Server

cd /d "%~dp0"

echo ========================================================
echo    SafeChat Python + MariaDB Server
echo ========================================================
echo.
echo [Sunucu baslatiliyor -> http://localhost:3000]
echo.

"C:\Program Files\PyManager\python.exe" main.py

pause
