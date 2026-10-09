@echo off
title Talknex Server

cd /d "%~dp0"

echo ========================================================
echo    Talknex Python + MariaDB Server
echo ========================================================
echo.
echo [Sunucu baslatiliyor -> http://localhost:3000]
echo.

python main.py

pause
