# Docker Compose: Runbook & Check‑Up Steps

This guide covers bringing the stack up with Docker Compose, verifying each service, and fixing common startup issues. Keep it in the project root alongside `docker-compose.yml`.

## Prerequisites
- Docker Engine + Docker Compose v2
- ~4 GB free RAM; outbound internet
- Free ports: 5432 (Postgres), 9092/19092 (Redpanda), 8123 (ClickHouse), 8081 (Flink), 8080 (Airflow), 8088 (External API)
- Optional: `jq` and `curl` on host for nicer output

## Quick start
```bash
# from project root
docker compose up -d

# see status (look for "healthy")
docker compose ps

# tail logs for the key services
docker compose logs -f postgres redpanda connect clickhouse flink-jobmanager flink-taskmanager flink-sql-runner redis
```
> Typical warm‑up is 30–60s as health checks pass and Flink downloads connector jars.

## Service map
| Service (compose) | Purpose | UI/Port |
|---|---|---|
| `postgres` | Source DB (content, engagement_events) | 5432 |
| `redpanda` | Kafka‑compatible broker | 9092 (in‑cluster), 19092 (host) |
| `connect` | Kafka Connect + Debezium + ClickHouse sink plugin | 8083 (REST) |
| `clickhouse` | Columnar analytics DB | 8123 (HTTP) |
| `redis` | Realtime leaderboard cache | 6379 |
| `flink-jobmanager` | Flink control plane | 8081 (Dashboard) |
| `flink-taskmanager` | Flink workers | — |
| `flink-sql-runner` | Submits/owns the SQL job | — |
| `event-generator` | Inserts synthetic events into Postgres | — |
| `http-sink` | Posts enriched events to external API | — |
| `external-api` | Mock external receiver | 8088 |
| `airflow` | Optional orchestration/bootstrapping | 8080 |

## Bring‑up order & health checks (what to expect)
1. **postgres** becomes `healthy` (`pg_isready`).
2. **redpanda** becomes `healthy` (broker reachable).
3. **connect** starts, installs ClickHouse sink plugin, exposes `/connector-plugins`.
4. **clickhouse** becomes `healthy` (`SELECT 1`).
5. **flink-jobmanager / taskmanager** start; runner downloads jars then submits SQL.
6. **event-generator** writes rows; Debezium publishes to `pg.public.engagement_events`.
7. **redis-agg** and **http-sink** consume from `thm.enriched.events`.
8. Optional **airflow** starts (SQLite) with the bootstrap DAG available.

## One‑shot smoke test
Use the provided helper to prove the data path end‑to‑end:
```bash
./fix_all.sh
```
This recreates a minimal ClickHouse sink, produces two sample enriched events, prints ClickHouse row count and the Redis top‑10 leaderboard.

## Verification: service‑by‑service
### Postgres
```bash
docker exec -it postgres psql -U app -d thm -c "\dt"
docker exec -it postgres psql -U app -d thm -c "SELECT count(*) FROM content;"
```

### Redpanda (Kafka)
```bash
docker exec -it redpanda rpk cluster info --brokers redpanda:9092
docker exec -it redpanda rpk topic list --brokers redpanda:9092
# expect pg.public.engagement_events and thm.enriched.events
```

### Kafka Connect
```bash
curl -s http://localhost:8083/connector-plugins | jq -r '.[].class' | grep ClickHouse
# com.clickhouse.kafka.connect.ClickHouseSinkConnector
curl -s http://localhost:8083/connectors | jq .
```

### Flink
```bash
curl -s http://localhost:8081/jobs | jq .
# expect a RUNNING job owned by flink-sql-runner
```

### ClickHouse
```bash
curl -sS 'http://localhost:8123/ping'
curl -s 'http://localhost:8123/?query=SELECT%20count()%20FROM%20thm.enriched_events'; echo
```

### Redis leaderboard
```bash
docker exec -it redis redis-cli ZREVRANGE thm:top:10m 0 9 WITHSCORES
```

### External API mock
```bash
curl -s http://localhost:8088/
# check consumer logs
docker compose logs --tail=100 http-sink external-api
```

## Operational commands
- Restart a single service without touching deps:
```bash
docker compose up -d --force-recreate --no-deps connect
```
- Tail logs for a service:
```bash
docker compose logs -f flink-sql-runner
```
- Full stop and clean volumes (fresh start):
```bash
docker compose down -v
```

## Manual Flink job submission (if runner isn’t used)
```bash
docker exec -it flink-jm bash -lc '
  bash /opt/flink/sql/download_flink_jars.sh &&
  /opt/flink/bin/sql-client.sh -f /opt/flink/sql/01_enrich.sql
'
```

## Resetting Kafka consumer offsets (Redis aggregator)
If the leaderboard stays empty but `thm.enriched.events` has data:
```bash
docker exec -it redpanda rpk group list --brokers redpanda:9092
# remove the aggregator group offsets
docker exec -it redpanda rpk group delete redis-agg --brokers redpanda:9092 || true
# restart the consumer
docker compose restart redis-agg
```

## Common startup issues
| Symptom | Likely cause | Fix |
|---|---|---|
| Debezium: `wal_level >= logical` | Postgres not in logical mode | Postgres container is started with `-c wal_level=logical`. If you modified the command, restore it and recreate the container. |
| Connect plugin missing | ClickHouse plugin not installed/visible | `docker compose up -d --force-recreate --no-deps connect` then check `/connector-plugins`. Installer is idempotent. |
| Flink: `TIMESTAMP_LTZ` unsupported | JSON serialization mismatch | Use the provided SQL where source uses `TIMESTAMP(3)` and sink casts `event_ts` to `STRING`. |
| Flink: sink does not support updates | Using `kafka` connector for changelog | Use `upsert-kafka` with `PRIMARY KEY (id)`; already set in `01_enrich.sql`. |
| Redis empty | Consumer at end of log or crashed | Reset group `redis-agg` as above and restart. |
| ClickHouse count stays 0 | Sink not created or topic empty | Recreate sink via `fix_all.sh`; verify topic has records with `rpk topic consume`. |

## Teardown & full reset
```bash
docker compose down -v
# optional: remove dangling images and networks
docker system prune -f
```

## Notes
- Use **service names** with `docker compose` (`flink-jobmanager`, not `flink-jm`).
- Health checks are defined; `docker compose ps` will show `healthy` when ready.
- The runner (`flink-sql-runner`) is idempotent: if the job terminates, recreate the service to resubmit.

