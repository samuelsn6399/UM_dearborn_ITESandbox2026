#!/usr/bin/env bash
# run_dashboard.sh
# ----------------
# One-click launcher for the Corridor Simulation Dashboard (macOS / Linux).
#
# Usage:
#     ./run_dashboard.sh
#
# Requires:
#     Python 3.9+ with requirements.txt installed.
#     Run once: pip install -r requirements.txt

set -e

echo ""
echo "====================================================="
echo " Corridor Simulation Platform  --  ITE Dashboard"
echo "====================================================="
echo ""

if ! command -v streamlit &>/dev/null; then
    echo "[ERROR] 'streamlit' not found on PATH."
    echo "        Please run:  pip install -r requirements.txt"
    exit 1
fi

echo "Starting dashboard at http://localhost:8501 ..."
echo "Press Ctrl+C to stop."
echo ""

streamlit run dashboard/app.py \
    --server.headless false \
    --browser.gatherUsageStats false
