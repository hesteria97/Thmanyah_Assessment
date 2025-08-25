CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TABLE IF NOT EXISTS content (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  content_type TEXT CHECK (content_type IN ('podcast','newsletter','video')),
  length_seconds INTEGER,
  publish_ts TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS engagement_events (
  id BIGSERIAL PRIMARY KEY,
  content_id UUID REFERENCES content(id),
  user_id UUID,
  event_type TEXT CHECK (event_type IN ('play','pause','finish','click')),
  event_ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  duration_ms INTEGER,
  device TEXT,
  raw_payload JSONB
);
CREATE INDEX IF NOT EXISTS idx_engagement_event_ts ON engagement_events (event_ts);
CREATE INDEX IF NOT EXISTS idx_engagement_content ON engagement_events (content_id);
