#!/usr/bin/env bash
set -euo pipefail
dest="/opt/flink/usrlib"
mkdir -p "$dest"
chmod 0777 "$dest" || true
cd "$dest"
grab() {
  url="$1"; file="${2:-$(basename "$url")}"
  if [ -f "$file" ]; then echo "Found $file"; return 0; fi
  echo "Downloading $file"
  tmp="${file}.tmp"
  curl -fSL --retry 4 --retry-delay 2 -o "$tmp" "$url"
  mv -f "$tmp" "$file"
}
grab https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.1.0-1.18/flink-sql-connector-kafka-3.1.0-1.18.jar
grab https://repo1.maven.org/maven2/org/apache/flink/flink-connector-jdbc/3.1.2-1.18/flink-connector-jdbc-3.1.2-1.18.jar
grab https://repo1.maven.org/maven2/org/apache/flink/flink-json/1.18.1/flink-json-1.18.1.jar
grab https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.7/postgresql-42.7.7.jar
echo "Flink libs ready"
