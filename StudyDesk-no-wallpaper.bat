@echo off
REM EMERGENCY FALLBACK: launches StudyDesk WITHOUT pinning the widget onto the
REM wallpaper. Use this only if pinning the widget ever restarts/freezes the PC.
REM It opens the app normally; the wallpaper countdown widget stays hidden.
cd /d "E:\PROJECTS\TO-DO BY FTA\desktop"
set SD_NO_WALLPAPER=1
start "" ".\node_modules\.bin\electron.cmd" .
