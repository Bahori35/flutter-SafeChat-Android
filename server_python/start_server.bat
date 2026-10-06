@echo off
setlocal enabledelayedexpansion

title WhatsApp Clone Server

echo ========================================================
echo    WhatsApp Clone Python + MariaDB Server
echo ========================================================
echo.

cd /d "%~dp0"

echo [1/2] Gerekli Python kutuphaneleri yukleniyor...
"C:\Program Files\PyManager\python.exe" -m pip install fastapi "uvicorn[standard]" pymysql cryptography passlib python-jose python-multipart "python-socketio>=5.11.2"

echo.
echo [2/2] Sunucu baslatiliyor -> http://localhost:3000
echo.

"C:\Program Files\PyManager\python.exe" main.py

pause
