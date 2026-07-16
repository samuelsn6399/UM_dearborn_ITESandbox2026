@echo off
REM run_dashboard.bat
REM -----------------
REM One-click launcher for the Corridor Simulation Dashboard (Windows).
REM
REM Usage:
REM     Double-click this file  — OR —
REM     From cmd.exe: run_dashboard.bat
REM
REM Requires:
REM     Python 3.9+ on PATH with requirements.txt installed.
REM     Run once: pip install -r requirements.txt

echo.
echo =====================================================
echo  Corridor Simulation Platform  --  ITE Dashboard
echo =====================================================
echo.

where streamlit >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] 'streamlit' not found on PATH.
    echo         Please run:  pip install -r requirements.txt
    pause
    exit /b 1
)

echo Starting dashboard at http://localhost:8501 ...
echo Press Ctrl+C to stop.
echo.

streamlit run dashboard/app.py --server.headless false --browser.gatherUsageStats false

pause
