#!/usr/bin/env bash
set -euo pipefail
echo "[airflow] migrating DB (SQLite)..."
airflow db migrate
if ! airflow users list | awk '{print $1}' | grep -qx 'airflow'; then
  echo "[airflow] creating admin user 'airflow'..."
  airflow users create --username airflow --password airflow --firstname A --lastname D --role Admin --email admin@example.com
else
  echo "[airflow] user 'airflow' already exists."
fi
airflow webserver -p 8080 &
exec airflow scheduler
