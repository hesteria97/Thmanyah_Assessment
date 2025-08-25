#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="/kafka/connect/clickhouse-kc"
mkdir -p "${PLUGIN_DIR}"
chmod -R a+rwx /kafka || true
chmod -R a+rwx "${PLUGIN_DIR}" || true

echo "[connect] Installing ClickHouse Kafka Connect Sink into ${PLUGIN_DIR} (if missing)..."

# if the connector is already visible, bail out early
if curl -fsS http://localhost:8083/connector-plugins 2>/dev/null | grep -q 'com.clickhouse.kafka.connect.ClickHouseSinkConnector'; then
  echo "[connect] ClickHouse sink already available. Skipping install."
  exit 0
fi

# Download latest release tag or fall back to v1.3.2
TAG="$(curl -fsSL https://api.github.com/repos/ClickHouse/clickhouse-kafka-connect/releases/latest | sed -n 's/.*"tag_name": *"\(v[^"]*\)".*/\1/p' || true)"
: "${TAG:=v1.3.2}"

# Try common asset names until one works
for NAME in \
  "clickhouse-kafka-connect-${TAG}.zip" \
  "clickhouse-kafka-connect-${TAG#v}.zip" \
  "clickhouse-kafka-connect-v${TAG#v}.zip"
do
  URL="https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/${TAG}/${NAME}"
  echo "[connect] trying ${URL}"
  if curl -fL -o "/tmp/${NAME}" "${URL}"; then
    if command -v unzip >/dev/null 2>&1; then
      unzip -oq "/tmp/${NAME}" -d "${PLUGIN_DIR}"
    elif command -v busybox >/dev/null 2>&1; then
      busybox unzip "/tmp/${NAME}" -d "${PLUGIN_DIR}"
    elif command -v jar >/dev/null 2>&1; then
      (cd "${PLUGIN_DIR}" && jar xf "/tmp/${NAME}")
    else
      echo "[connect] no unzip tool available"; exit 1
    fi
    rm -f "/tmp/${NAME}"
    break
  fi
done

# Do NOT flatten jars; keep the vendor's directory layout.
# Just make sure permissions are readable.
chmod -R a+rX "${PLUGIN_DIR}" || true
echo "[connect] Installed contents:"
ls -la "${PLUGIN_DIR}" || true
