CREATE TABLE IF NOT EXISTS enriched_events (
  id UInt64,
  content_id String,
  user_id String,
  event_type LowCardinality(String),
  event_ts DateTime64(3),
  device LowCardinality(String),
  content_type LowCardinality(String),
  length_seconds Int32,
  engagement_seconds Nullable(Decimal(10,2)),
  engagement_pct Nullable(Decimal(5,2)),
  raw_payload String
)
ENGINE = ReplacingMergeTree
ORDER BY (event_ts, id);
