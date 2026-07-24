@echo off
REM Fully restarts StudyDesk so code/theme updates take effect.
REM (The always-running widget keeps the old app alive, so a normal re-open
REM reuses the old version — this kills it first, then reopens.)
taskkill /IM electron.exe /F >nul 2>&1
ping -n 2 127.0.0.1 >nul
cd /d "E:\PROJECTS\TO-DO BY FTA\desktop"
start "" ".\node_modules\.bin\electron.cmd" .
