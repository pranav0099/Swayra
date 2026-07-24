@echo off
REM Launches StudyDesk as a standalone desktop app (offline, no server needed).
cd /d "E:\PROJECTS\TO-DO BY FTA\desktop"
if not exist "node_modules\electron" (
  echo Installing the app runtime the first time, please wait...
  call npm install
)
start "" ".\node_modules\.bin\electron.cmd" .
