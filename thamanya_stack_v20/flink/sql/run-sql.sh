#!/usr/bin/env bash
set -euo pipefail
bash /opt/flink/sql/download_flink_jars.sh
echo "[runner] waiting for Flink JM REST @ http://flink-jm:8081 ..."
for i in {1..60}; do
  if curl -fsS http://flink-jm:8081/jobs >/dev/null 2>&1; then break; fi
  sleep 2
done
echo "[runner] submitting SQL..."
/opt/flink/bin/sql-client.sh -f /opt/flink/sql/01_enrich.sql || { echo "[runner] SQL failed"; exit 1; }
echo "[runner] tailing forever"; tail -f /dev/null
