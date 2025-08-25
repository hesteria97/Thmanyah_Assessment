#!/usr/bin/env bash
set -euo pipefail
CONNECT=http://localhost:8083
CH=http://localhost:8123
DB=thm
TABLE=enriched_events
TOPIC=thm.enriched.events
SINK=clickhouse.sink.enriched
echo "== A) ClickHouse reachable and DB/table exist =="
curl -fsS "$CH/ping"
curl -fsS "$CH/?database=$DB" --data-binary @airflow/dags/resources/clickhouse.create_table.sql >/dev/null
echo "== B) Recreate minimal ClickHouse sink with best-effort datetime =="
cat > /tmp/sink.min.json <<JSON
{
  "name": "$SINK",
  "config": {
    "connector.class": "com.clickhouse.kafka.connect.ClickHouseSinkConnector",
    "tasks.max": "1",
    "topics": "$TOPIC",
    "topic2TableMap": "$TOPIC=$TABLE",
    "hostname": "clickhouse",
    "port": "8123",
    "ssl": "false",
    "database": "$DB",
    "username": "default",
    "password": "",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "clickhouseSettings": "date_time_input_format=best_effort",
    "errors.tolerance": "none"
  }
}
JSON
curl -s -X DELETE "$CONNECT/connectors/$SINK" >/dev/null 2>&1 || true
curl -s -o /dev/null -w "create: HTTP %{http_code}\n" -H 'Content-Type: application/json' -X POST --data @/tmp/sink.min.json "$CONNECT/connectors"
echo "== C) Produce two test events =="
docker exec -i redpanda bash -lc 'cat <<EOF | rpk topic produce '"$TOPIC"' --brokers redpanda:9092
{"id":1002001,"content_id":"c-redis-A","user_id":"u-test","event_type":"play","event_ts":"2025-08-23 05:40:00","device":"web-chrome","content_type":"video","length_seconds":120,"engagement_seconds":10.5,"engagement_pct":8.75,"raw_payload":"{}"}
{"id":1002002,"content_id":"c-redis-B","user_id":"u-test","event_type":"finish","event_ts":"2025-08-23 05:41:00","device":"web-chrome","content_type":"video","length_seconds":120,"engagement_seconds":120.0,"engagement_pct":100.0,"raw_payload":"{}"}
EOF'
echo "== D) ClickHouse count and Redis top-10 =="
curl -s "$CH/?query=SELECT%20count()%20FROM%20$DB.$TABLE"; echo
docker exec -it redis redis-cli ZREVRANGE thm:top:10m 0 9 WITHSCORES || true
