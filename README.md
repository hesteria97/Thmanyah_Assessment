# THAMANYA FAN‑OUT STACK

Quickstart (Text Edition)

This is the minimal, copy‑pasteable guide to run and verify the stack. Keep it in the project root next to `docker-compose.yml`.

## Architecture

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


## Contents

1. Requirements
2. Start the stack
3. Health checks
4. Validate end‑to‑end data
5. Useful commands
6. Troubleshooting (fast)
7. Monitoring (Grafana & Prometheus)

## 1) Requirements

* Docker Engine + Docker Compose v2
* \~4 GB free RAM
* Open ports: 5432, 9092/19092, 8123, 8081, 8080, 8088
* Optional host tools: `curl`, `jq`

## 2) Start the stack

From the project root:

```bash
docker compose up -d
docker compose ps
```

Expect services to become **healthy** within \~30–60 seconds.

## 3) Health checks

* Flink UI:      [http://localhost:8081](http://localhost:8081)
* Airflow UI:    [http://localhost:8080](http://localhost:8080)  (user: `airflow`, pass: `airflow`)
* External API:  [http://localhost:8088](http://localhost:8088)
* ClickHouse ping:

```bash
curl -sS http://localhost:8123/ping
```

## 4) Validate end‑to‑end data

Run the smoke test (creates ClickHouse sink, produces samples, checks counts):

```bash
./fix_all.sh
```

Manual checks:

```bash
# Kafka enriched topic
docker exec -it redpanda rpk topic consume thm.enriched.events -n 3 --brokers redpanda:9092

# ClickHouse row count
curl -s 'http://localhost:8123/?query=SELECT%20count()%20FROM%20thm.enriched_events'; echo

# Redis leaderboard (last 10 minutes)
docker exec -it redis redis-cli ZREVRANGE thm:top:10m 0 9 WITHSCORES
```

## 5) Useful commands

Logs (use **compose service names**):

```bash
docker compose logs --tail=200 postgres redpanda connect clickhouse \
  flink-jobmanager flink-taskmanager flink-sql-runner redis
```

Restart a single service without deps:

```bash
docker compose up -d --force-recreate --no-deps connect
```

Full reset (removes volumes):

```bash
docker compose down -v
```

Submit the Flink job manually (if needed):

```bash
docker exec -it flink-jm bash -lc 'bash /opt/flink/sql/download_flink_jars.sh && \
  /opt/flink/bin/sql-client.sh -f /opt/flink/sql/01_enrich.sql'
```

## 6) Troubleshooting (fast)

* **Debezium requires `wal_level=logical`:** Postgres is started with it. If you changed the container command, restore it and recreate `postgres`.
* **ClickHouse sink plugin not found (Connect):**

  ```bash
  docker compose up -d --force-recreate --no-deps connect
  curl -s http://localhost:8083/connector-plugins | jq -r '.[].class' | grep ClickHouse
  ```
* **Flink `TIMESTAMP_LTZ` unsupported:** Use the provided SQL. Source uses `TIMESTAMP(3)`; sink casts `event_ts` to `STRING`.
* **Flink sink rejects updates/deletes:** Use `upsert-kafka` with `PRIMARY KEY (id)` (already set in `flink/sql/01_enrich.sql`).
* **Redis leaderboard empty but Kafka has data:**

  ```bash
  docker exec -it redpanda rpk group delete redis-agg --brokers redpanda:9092 || true
  docker compose restart redis-agg
  ```
* **ClickHouse row count stays 0:** Recreate the sink and produce a test record: `./fix_all.sh`

## 7) Monitoring (Grafana & Prometheus)

Add real‑time monitoring for the whole stack. Recommended exporters/targets:

* **PostgreSQL:** `postgres_exporter`
* **Flink JM/TM:** JMX exporter (Java agent) exposing Flink metrics to Prometheus
* **Redpanda (Kafka):** native Prometheus endpoints
* **ClickHouse:** built‑in `/metrics`
* **Redis:** `redis_exporter`
* **Host/container:** `node_exporter`
* **Dashboards:** Grafana with prebuilt dashboards

> This project has been validated with Grafana/Prometheus locally and is ready for future real‑time monitoring.

Suggested compose override:

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    ports: ["9090:9090"]
  grafana:
    image: grafana/grafana:latest
    ports: ["3000:3000"]
    volumes:
      - ./monitoring/provisioning:/etc/grafana/provisioning
```

End of file.






































مشروع Thamanya Fan‑Out Stack — دليل سريع (نسخة نصية)
=====================================================

هذا الملف هو دليل مختصر قابل للنسخ واللصق لتشغيل الحزمة والتحقق منها. احتفظ به في جذر المشروع بجانب ملف `docker-compose.yml`.

المحتويات
---------
1) المتطلبات
2) تشغيل الحاويات
3) فحوصات الصحة
4) التحقق من تدفق البيانات طرفًا إلى طرف
5) أوامر مفيدة
6) استكشاف الأخطاء وإصلاحها (مختصر)

1) المتطلبات
-------------
- محرك Docker و Docker Compose v2
- ذاكرة متاحة ~4 جيجابايت
- فتح المنافذ: 5432 و 9092/19092 و 8123 و 8081 و 8080 و 8088
- أدوات اختيارية على المضيف: curl و jq

2) تشغيل الحاويات
------------------
من جذر المشروع (حيث يوجد `docker-compose.yml`):

  docker compose up -d
  docker compose ps

توقع أن تصبح الخدمات "صحية" خلال 30–60 ثانية.

3) فحوصات الصحة
----------------
- واجهة Flink:      http://localhost:8081
- واجهة Airflow:    http://localhost:8080  (المستخدم: airflow / كلمة المرور: airflow)
- واجهة الـ API الخارجية:  http://localhost:8088
- فحص ClickHouse:

  curl -sS http://localhost:8123/ping

4) التحقق من تدفق البيانات طرفًا إلى طرف
-----------------------------------------
شغّل سكربت الاختبار السريع (ينشئ مُصرّف ClickHouse، ويُنتج عينات، ويتحقق من العدادات):

  ./fix_all.sh

التحقق اليدوي:
- موضوع Kafka المثرى:

  docker exec -it redpanda rpk topic consume thm.enriched.events -n 3 --brokers redpanda:9092

- عدد الصفوف في ClickHouse:

  curl -s 'http://localhost:8123/?query=SELECT%20count()%20FROM%20thm.enriched_events'; echo

- لوح الصدارة في Redis (آخر 10 دقائق):

  docker exec -it redis redis-cli ZREVRANGE thm:top:10m 0 9 WITHSCORES

5) أوامر مفيدة
---------------
- السجلات (أسماء خدمات compose):

  docker compose logs --tail=200 postgres redpanda connect clickhouse \
    flink-jobmanager flink-taskmanager flink-sql-runner redis

- إعادة تشغيل خدمة واحدة دون التأثير على التبعيات:

  docker compose up -d --force-recreate --no-deps connect

- إعادة تعيين كاملة (إزالة المجلدات الدائمة):

  docker compose down -v

- إرسال مهمة Flink يدويًا (إذا لزم):

  docker exec -it flink-jm bash -lc 'bash /opt/flink/sql/download_flink_jars.sh && \
    /opt/flink/bin/sql-client.sh -f /opt/flink/sql/01_enrich.sql'

6) استكشاف الأخطاء وإصلاحها (مختصر)
------------------------------------
- خطأ Debezium حول wal_level=logical:
  يجب أن يعمل Postgres بوضع «الترميز المنطقي». ملف compose يضبط ذلك مسبقًا.

- لم يتم العثور على مُصرّف ClickHouse في Connect:
  أعد إنشاء خدمة Connect ثم تحقق من نقطة الإضافات:
    docker compose up -d --force-recreate --no-deps connect
    curl -s http://localhost:8083/connector-plugins | jq -r '.[].class' | grep ClickHouse

- خطأ Flink: ‎TIMESTAMP_LTZ غير مدعوم:
  استخدم ملف SQL المرفق. المصدر يستخدم TIMESTAMP(3) والمخرج يحول event_ts إلى نص (STRING).

- رافض مخزن Flink للتحديثات/الحذف:
  استخدم `upsert-kafka` مع مفتاح أساسي (PRIMARY KEY id). مُعدّ مسبقًا في `flink/sql/01_enrich.sql`.

- Redis فارغ رغم وجود بيانات Kafka:
  صفّر مجموعة المستهلك ثم أعد تشغيل المجمع:
    docker exec -it redpanda rpk group delete redis-agg --brokers redpanda:9092 || true
    docker compose restart redis-agg

- عداد ClickHouse يبقى صفرًا:
  أعد إنشاء المخزن وأنتج سجل اختبار:
    ./fix_all.sh
وشكراا،،،،
