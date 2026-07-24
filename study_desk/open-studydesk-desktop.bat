@echo off
REM Serves the StudyDesk web build locally, then opens it in your browser.
REM Click "Install" in the address bar to add it as a Windows app.
REM (After it's installed once, it works offline even without this window.)
cd /d "E:\PROJECTS\TO-DO BY FTA\study_desk\build\web"
echo Starting StudyDesk at http://127.0.0.1:5500  (leave this window open)
start "" "http://127.0.0.1:5500"
python -m http.server 5500 --bind 127.0.0.1
