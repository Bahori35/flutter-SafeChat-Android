@echo off
chcp 65001 > nul
title WhatsApp Clone - Python MariaDB Server

echo ========================================================
echo   WhatsApp Clone Python + MariaDB Sunucusu Başlatılıyor
echo ========================================================
echo.

cd /d "%~dp0"

echo [Gerekli Python paketleri kontrol ediliyor...]
pip install -r requirements.txt

echo.
echo [Sunucu başlatılıyor -> http://localhost:3000]
echo.
python main.py

pause
