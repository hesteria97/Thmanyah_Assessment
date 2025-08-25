<!-- Save this file as README.md -->

# Thamanya Fan‑Out Stack

Event streaming pipeline from PostgreSQL to three sinks (ClickHouse, Redis, external HTTP) with Flink SQL enrichment and Debezium CDC.

* **Source:** PostgreSQL (`content`, `engagement_events`)
* **CDC → Kafka:** Debezium (Kafka Connect)
* **Broker:** Redpanda (Kafka API)
* **Processing:** Flink SQL (enrich + transform)
* **Sinks:** ClickHouse (analytics), Redis (real‑time leaderboard), External HTTP API (mock)
* **Orchestration:** Airflow (optional bootstrap tasks)
* **Synthetic load:** Event generator (Python)

## Architecture

```mermaid
flowchart LR
  classDef kafka fill:#f1f8ff,stroke:#0366d6,color:#000;

  subgraph PG[PostgreSQL]
    A[content]
    B[engagement_events]
  end

  subgraph Debezium[Kafka Connect + Debezium PG]
    C[CDC Source: pg.public.engagement_events]
  end

  subgraph RP[Redpanda (Kafka)]
    RP1[(Kafka)]
    RP2[(Kafka)]
    class RP2 kafka
  end

  subgraph Flink[Flink SQL]
    F[Join, derive, compute]
  end

  subgraph Sinks[Fan-out Sinks]
    CH[ClickHouse<br/>thm.enriched_events]
    RD[Redis<br/>thm:top:10m ZSET]
    EXT[External HTTP API]
  end

  A -->|dimension lookup| F
  B -->|WAL logical decode| C
  C -->|pg.public.engagement_events| RP1
  RP1 --> F
  F -->|thm.enriched.events| RP2
  RP2 --> CH
  RP2 --> RD
  RP2 --> EXT
```

## Data model

**PostgreSQL**

* `content(id, slug, title, content_type, length_seconds, publish_ts)`
* `engagement_events(id, content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload)`

**Enrichment**

* `engagement_seconds = duration_ms / 1000`
* `engagement_pct = (engagement_seconds / length_seconds) * 100` (NULL if inputs missing)

**Kafka topics**

* `pg.public.engagement_events` (Debezium JSON, changelog)
* `thm.enriched.events` (upsert‑kafka, key = id)

**ClickHouse**

* `thm.enriched_events` ReplacingMergeTree ordered by `(event_ts, id)`

**Redis**

* Rolling top content ZSET for last 10 minutes: `thm:top:10m`
  Scoring: play/finish = +1.0, click = +0.2, pause = 0

## Repository layout

```
.
├─ docker-compose.yml
├─ fix_all.sh                       # smoke test: CH sink + 2 sample records + Redis check
├─ db/
│  └─ init/                         # Postgres schema + seed
├─ connectors/
│  ├─ install-clickhouse-plugin.sh  # safe installer for ClickHouse Kafka Connect sink
│  └─ clickhouse-kc/                # plugin dir (populated at runtime)
├─ flink/
│  └─ sql/
│     ├─ download_flink_jars.sh     # fetch Flink connectors (kafka, jdbc, json, postgres)
│     ├─ run-sql.sh                 # waits JM then submits SQL
│     └─ 01_enrich.sql              # source + lookup + sink + INSERT
├─ generator/
│  └─ generator.py                  # inserts random engagement rows into Postgres
├─ consumers/
│  ├─ requirements.txt
│  ├─ redis_agg.py                  # consumes enriched topic → updates Redis
│  └─ http_sink.py                  # consumes enriched topic → POST to external API
├─ external/
│  └─ app.py                        # simple Flask app to receive events
└─ airflow/
   ├─ entrypoint-sqlite.sh          # SQLite-based Airflow entrypoint
   └─ dags/
      ├─ thamanya_bootstrap.py      # optional bootstrap DAG
      └─ resources/
         ├─ clickhouse.create_table.sql
         ├─ pg-engagement-source.json
         └─ clickhouse-sink.json
```

## Requirements

* Docker Engine + Docker Compose v2
* \~4 GB RAM free for containers
* Ports free:

  * Postgres 5432
  * Redpanda 9092 (19092 external)
  * ClickHouse 8123
  * Flink 8081
  * Airflow 8080
  * External API 8088
* Optional CLI tools: `jq`, `curl`, `rpk` (already inside the Redpanda container)

## Quick start

```bash
docker compose up -d
# wait ~30–60s for healthchecks
./fix_all.sh   # smoke test: create CH sink, produce 2 sample events, CH count + Redis top‑10
```

## Quickstart (visual)

![Thamanya Quickstart Flow](./quickstart_flow.png)

**Order of operations:**
1. Start the stack: `docker compose up -d`
2. Smoke test: `./fix_all.sh`
3. Open Airflow: `http://localhost:8080` (user `airflow`, password `airflow`)
4. Trigger the DAG: `thamanya_bootstrap`
5. Tasks run in order:
   - `clickhouse_create_db`
   - `clickhouse_create_table`
   - `wait_for_clickhouse_sink_plugin`
   - `register_debezium_source`
   - `register_clickhouse_sink`

### Service URLs

* Flink Dashboard: [http://localhost:8081](http://localhost:8081)
* Airflow Web UI: [http://localhost:8080](http://localhost:8080)  (user: `airflow`, password: `airflow`)
* External mock API: [http://localhost:8088/](http://localhost:8088/)

### What starts automatically

* **Postgres** with schema + seed data
* **Redpanda** broker
* **Kafka Connect** with Debezium PG connector plugin and ClickHouse sink plugin installation
* **Flink JM/TM**; **flink‑sql‑runner** downloads connector jars and submits the SQL
* **Event generator** inserts random rows to Postgres every 5s
* **Redis aggregator** and **HTTP sink** consume `thm.enriched.events`
* **Airflow** starts (SQLite), with an optional DAG for CH table creation and connector registration

> If you want Airflow to register the Debezium source and CH sink instead of `fix_all.sh`, trigger the DAG:
>
> ```bash
> docker exec -it airflow airflow dags trigger thamanya_bootstrap
> ```

## Validation checklist

```bash
# 1) Flink job present and RUNNING
curl -s http://localhost:8081/jobs | jq .

# 2) Debezium source connector is RUNNING
curl -s http://localhost:8083/connectors/pg.engagement.source/status | jq '.connector.state,.tasks[].state'

# 3) Enriched Kafka topic has messages
docker exec -it redpanda rpk topic consume thm.enriched.events -n 3 --brokers redpanda:9092

# 4) ClickHouse row count increases
curl -s 'http://localhost:8123/?query=SELECT%20count()%20FROM%20thm.enriched_events'; echo

# 5) Redis 10‑minute leaderboard
docker exec -it redis redis-cli ZREVRANGE thm:top:10m 0 9 WITHSCORES

# 6) External API received posts
docker compose logs --tail=80 external-api http-sink
```

## Operational notes

* **Flink SQL (`01_enrich.sql`)**

  * Source reads Debezium JSON from `pg.public.engagement_events`.
  * Lookup table `dim_content` is a **TEMPORARY JDBC table** so it exists in the same session as the `INSERT`.
  * Sink uses **`upsert-kafka`** with `PRIMARY KEY (id)` to accept changelog updates.
  * `event_ts` is written as **STRING** to keep JSON serialization compatible across sinks.
* **Exactly-once:** Checkpointing is enabled (10s). For Kafka sinks, Flink can be configured for stronger guarantees; this demo uses defaults appropriate for local runs.
* **Backfill:** Start Debezium with an initial snapshot (or reconfigure and restart the source connector) and let Flink read from earliest offsets. This stack already sets `scan.startup.mode = earliest-offset`.

## Common issues & fixes

| Symptom / Log                                                         | Cause                                              | Fix                                                                                                                                                                                                                      |
| --------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ERROR: logical decoding requires wal_level >= logical` (Debezium)    | Postgres WAL not configured                        | We start Postgres with `wal_level=logical`. If you changed it, restore the `command:` in `docker-compose.yml` for Postgres.                                                                                              |
| `Connector configuration is invalid... The connection attempt failed` | Kafka Connect can’t reach Postgres                 | Ensure `postgres` service is healthy; verify network (`docker compose ps`) and credentials in `pg-engagement-source.json`.                                                                                               |
| ClickHouse sink plugin not found                                      | Plugin didn’t install or permissions               | The installer runs before Connect starts and leaves plugin under `/kafka/connect/clickhouse-kc`. Restart Connect: `docker compose up -d --force-recreate --no-deps connect`. Verify with `curl :8083/connector-plugins`. |
| `Flink distribution jar not found...`                                 | Flink image missing libs                           | JM/TM/runner containers run `download_flink_jars.sh` on start; ensure outbound network works. If needed, `docker exec -it flink-jm bash -lc 'bash /opt/flink/sql/download_flink_jars.sh'`.                               |
| `Unsupported type: TIMESTAMP_LTZ(3)`                                  | JSON sink didn’t like LTZ                          | We use `TIMESTAMP(3)` in the source and cast to `STRING` in the sink. Use the provided `01_enrich.sql`.                                                                                                                  |
| `Table sink ... doesn't support consuming update and delete changes`  | Plain `kafka` sink can’t accept changelogs         | Use **`upsert-kafka`** with a primary key. Already set in `01_enrich.sql`.                                                                                                                                               |
| Redis leaderboard empty                                               | Aggregator stuck on committed offsets or no events | Check `docker compose logs redis-agg`. Reset group: `docker exec -it redpanda rpk group delete redis-agg --brokers redpanda:9092 && docker compose restart redis-agg`. Produce a test record to `thm.enriched.events`.   |
| `UnsupportedCodecError: Libraries for snappy`                         | Kafka messages compressed                          | We install `python-snappy` and `lz4`. If you override image, keep those deps.                                                                                                                                            |
| `mv ... are the same file` in Connect installer                       | Over‑aggressive flattening of plugin jars          | Installer is now idempotent and doesn’t flatten. Use the provided `install-clickhouse-plugin.sh`.                                                                                                                        |

## Manual controls

### Start/stop specific services

```bash
docker compose up -d postgres redpanda connect clickhouse redis
docker compose up -d flink-jobmanager flink-taskmanager flink-sql-runner
docker compose up -d event-generator redis-agg http-sink external-api airflow

docker compose stop
docker compose down -v   # full cleanup (volumes)
```

### Submit the Flink job manually (if needed)

```bash
docker exec -it flink-jm bash -lc '
  bash /opt/flink/sql/download_flink_jars.sh &&
  /opt/flink/bin/sql-client.sh -f /opt/flink/sql/01_enrich.sql
'
```

### Inspect Kafka

```bash
docker exec -it redpanda rpk topic list --brokers redpanda:9092
docker exec -it redpanda rpk topic describe thm.enriched.events --brokers redpanda:9092
docker exec -it redpanda rpk topic consume thm.enriched.events -n 5 --brokers redpanda:9092
```

### Query ClickHouse

```bash
curl -s 'http://localhost:8123/?query=SELECT%20count()%20FROM%20thm.enriched_events'; echo
curl -s 'http://localhost:8123/?query=SELECT%20content_id,%20count()%20FROM%20thm.enriched_events%20GROUP%20BY%201%20ORDER%20BY%202%20DESC%20LIMIT%205' | column -t
```

### Redis leaderboard

```bash
docker exec -it redis redis-cli ZREVRANGE thm:top:10m 0 9 WITHSCORES
```

## Airflow (optional bootstrap)

* DAG: `thamanya_bootstrap`

  * `clickhouse_create_db` and `clickhouse_create_table`
  * `register_debezium_source` (POST to Connect)
  * `register_clickhouse_sink` (POST to Connect)
* Trigger manually:

  ```bash
  docker exec -it airflow airflow dags trigger thamanya_bootstrap
  ```

## Extending and hardening

* **Schema evolution:** Enable Debezium schema change topics and handle them in Flink if you plan to evolve source tables.
* **Exactly-once end‑to‑end:** Tune Flink checkpointing and Kafka transactional settings for production.
* **Backfill:** Recreate Debezium source with an initial snapshot and reset offsets; Flink reads from earliest.
* **Observability:** Add Grafana/Prometheus for broker and Flink metrics, plus Kafka Connect REST health probes.

## Service names vs container names

Use **service names** with `docker compose`, and container names with `docker logs`.

| Service             | Container          |
| ------------------- | ------------------ |
| `flink-jobmanager`  | `flink-jm`         |
| `flink-taskmanager` | `flink-tm`         |
| `flink-sql-runner`  | `flink-sql-runner` |
| `connect`           | `connect`          |
| `redpanda`          | `redpanda`         |
| `clickhouse`        | `clickhouse`       |
| `postgres`          | `postgres`         |
| `redis`             | `redis`            |
| `airflow`           | `airflow`          |
