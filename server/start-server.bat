@echo off
REM ===== StudyDesk backend launcher =====
REM Double-click this file to start the server. Keep this window OPEN while
REM you use the app's sync / admin panel. Close the window to stop the server.

cd /d "%~dp0"

echo Starting StudyDesk server...
echo Admin panel: http://127.0.0.1:4000/admin   (login: admin / admin123)
echo Press Ctrl+C or close this window to stop.
echo.

node --disable-warning=ExperimentalWarning server.js

echo.
echo Server stopped. Press any key to close.
pause >nul
