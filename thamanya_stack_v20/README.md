# Thamanya Fanout Stack v20
# THAMANYA FAN-OUT STACK — QUICKSTART (TEXT EDITION)

This file is the minimal, copy-pasteable guide to run and verify the stack. Keep it in the project root alongside `docker-compose.yml`.

## Contents

1. Requirements

2. Start the stack

3. Health checks

4. Validate end-to-end data

5. Useful commands

6. Troubleshooting (fast)



---

* Docker Engine + Docker Compose v2
* \~4 GB free RAM
* Open ports: 5432, 9092/19092, 8123, 8081, 8080, 8088
* Optional tools on host: curl, jq

2. Start the stack

---

From the project root (where `docker-compose.yml` lives):

docker compose up -d
docker compose ps

Expect services to become "healthy" within \~30–60 seconds.

3. Health checks

---

* Flink UI:      [http://localhost:8081](http://localhost:8081)
* Airflow UI:    [http://localhost:8080](http://localhost:8080)   (user: airflow / pass: airflow)
* External API:  [http://localhost:8088](http://localhost:8088)
* ClickHouse ping:

  curl -sS [http://localhost:8123/ping](http://localhost:8123/ping)

4. Validate end-to-end data

---

Run the smoke test script (creates ClickHouse sink, produces sample events, checks counts):

./fix\_all.sh

Manual inspection:

* Kafka enriched topic:

  docker exec -it redpanda rpk topic consume thm.enriched.events -n 3 --brokers redpanda:9092

* ClickHouse row count:

  curl -s '[http://localhost:8123/?query=SELECT%20count()%20FROM%20thm.enriched\_events](http://localhost:8123/?query=SELECT%20count%28%29%20FROM%20thm.enriched_events)'; echo

* Redis leaderboard (last 10 minutes):

  docker exec -it redis redis-cli ZREVRANGE thm\:top:10m 0 9 WITHSCORES

5. Useful commands

---

* Logs (compose service names):

  docker compose logs --tail=200 postgres redpanda connect clickhouse&#x20;
  flink-jobmanager flink-taskmanager flink-sql-runner redis

* Restart a single service without touching deps:

  docker compose up -d --force-recreate --no-deps connect

* Full reset (removes volumes):

  docker compose down -v

* Submit the Flink job manually (if needed):

  docker exec -it flink-jm bash -lc 'bash /opt/flink/sql/download\_flink\_jars.sh &&&#x20;
  /opt/flink/bin/sql-client.sh -f /opt/flink/sql/01\_enrich.sql'

6. Troubleshooting (fast)

---

* Debezium error about wal\_level=logical:
  Postgres must run with logical decoding. The compose file already sets it. Recreate `postgres` if you changed it.

* ClickHouse sink plugin not found in Connect:
  Recreate just Connect and recheck plugins endpoint:
  docker compose up -d --force-recreate --no-deps connect
  curl -s [http://localhost:8083/connector-plugins](http://localhost:8083/connector-plugins) | jq -r '.\[].class' | grep ClickHouse

* Flink "TIMESTAMP\_LTZ" unsupported:
  Use the provided SQL. Source uses TIMESTAMP(3); sink casts event\_ts to STRING.

* Flink sink rejects updates/deletes:
  Use `upsert-kafka` with PRIMARY KEY (id). Already set in `flink/sql/01_enrich.sql`.

* Redis leaderboard empty but Kafka has data:
  Reset the consumer group and restart the aggregator:
  docker exec -it redpanda rpk group delete redis-agg --brokers redpanda:9092 || true
  docker compose restart redis-agg

* ClickHouse row count stays 0:
  Recreate the sink and produce a test record:
  ./fix\_all.sh

