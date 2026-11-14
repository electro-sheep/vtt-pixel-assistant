@echo off
title VTT Pixel Assistant v2.0 Launcher
cd /d "%~dp0"
taskkill /F /IM vtt_assistant.exe >nul 2>&1
echo Starting Local Faster-Whisper CUDA & Dyslexia Engine v2.0...
start "" /B python backend\vtt_engine.py
timeout /t 2 /nobreak >nul
if exist "build\windows\x64\runner\Release\vtt_assistant.exe" (
    echo Launching VTT Pixel Assistant Overlay...
    start "" /D "%~dp0build\windows\x64\runner\Release" "%~dp0build\windows\x64\runner\Release\vtt_assistant.exe"
) else (
    echo Building and running Flutter Windows Overlay...
    flutter run -d windows
)
