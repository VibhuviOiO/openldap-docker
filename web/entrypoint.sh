#!/bin/sh
set -e

echo "Starting LDAP Manager..."

# Start Vite dev server in background
cd /frontend
npm run dev -- --host 0.0.0.0 &

# Start FastAPI
cd /app
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
