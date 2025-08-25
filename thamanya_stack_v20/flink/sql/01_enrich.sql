-- Load connectors
ADD JAR 'file:///opt/flink/usrlib/flink-sql-connector-kafka-3.1.0-1.18.jar';
ADD JAR 'file:///opt/flink/usrlib/flink-connector-jdbc-3.1.2-1.18.jar';
ADD JAR 'file:///opt/flink/usrlib/flink-json-1.18.1.jar';
ADD JAR 'file:///opt/flink/usrlib/postgresql-42.7.7.jar';

-- Source: Debezium CDC topic (no unsupported options)
DROP TABLE IF EXISTS engagement_src;
CREATE TEMPORARY TABLE engagement_src (
  id BIGINT,
  content_id STRING,
  user_id STRING,
  event_type STRING,
  event_ts TIMESTAMP(3),                 -- no LTZ
  duration_ms INT,
  device STRING,
  raw_payload STRING,
  proc_time AS PROCTIME()
) WITH (
  'connector' = 'kafka',
  'topic' = 'pg.public.engagement_events',
  'properties.bootstrap.servers' = 'redpanda:9092',
  'scan.startup.mode' = 'earliest-offset',
  'value.format' = 'debezium-json',
  'value.debezium-json.ignore-parse-errors' = 'true',
  'value.debezium-json.timestamp-format.standard' = 'ISO-8601'
);

-- Lookup dim via JDBC (TEMPORARY so it exists in this session)
DROP TABLE IF EXISTS dim_content;
CREATE TEMPORARY TABLE dim_content (
  id STRING PRIMARY KEY NOT ENFORCED,
  slug STRING,
  title STRING,
  content_type STRING,
  length_seconds INT
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:postgresql://postgres:5432/thm',
  'table-name' = 'content',
  'driver' = 'org.postgresql.Driver',
  'username' = 'app',
  'password' = 'app',
  'lookup.cache.max-rows' = '5000',
  'lookup.cache.ttl' = '10min',
  'lookup.max-retries' = '3'
);

-- Sink: UPSERT-KAFKA accepts changelog streams (required for Debezium + joins)
DROP TABLE IF EXISTS enriched_out;
CREATE TABLE enriched_out (
  id BIGINT,
  content_id STRING,
  user_id STRING,
  event_type STRING,
  event_ts STRING,                       -- cast to string to avoid LTZ issues
  device STRING,
  content_type STRING,
  length_seconds INT,
  engagement_seconds DECIMAL(10,2),
  engagement_pct DECIMAL(5,2),
  raw_payload STRING,
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'upsert-kafka',
  'topic' = 'thm.enriched.events',
  'properties.bootstrap.servers' = 'redpanda:9092',
  'key.format' = 'json',
  'value.format' = 'json',
  'key.json.ignore-parse-errors' = 'true',
  'value.json.ignore-parse-errors' = 'true',
  'value.json.timestamp-format.standard' = 'ISO-8601'
);

-- Enrichment + lookup join + write
INSERT INTO enriched_out
SELECT
  e.id,
  e.content_id,
  e.user_id,
  e.event_type,
  CAST(e.event_ts AS STRING) AS event_ts,
  e.device,
  c.content_type,
  c.length_seconds,
  CASE WHEN e.duration_ms IS NULL THEN NULL
       ELSE ROUND(CAST(e.duration_ms AS DECIMAL(18,2)) / 1000.0, 2)
  END AS engagement_seconds,
  CASE
    WHEN e.duration_ms IS NULL OR c.length_seconds IS NULL OR c.length_seconds = 0
      THEN NULL
    ELSE ROUND( (CAST(e.duration_ms AS DECIMAL(18,2)) / 1000.0)
                / CAST(c.length_seconds AS DECIMAL(18,2)) * 100, 2)
  END AS engagement_pct,
  e.raw_payload
FROM engagement_src AS e
LEFT JOIN dim_content FOR SYSTEM_TIME AS OF e.proc_time AS c
ON e.content_id = c.id
WHERE e.event_type IS NOT NULL;
