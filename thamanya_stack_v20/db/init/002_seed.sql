INSERT INTO content (slug, title, content_type, length_seconds)
SELECT 'c-'||g, 'Content #'||g,
       (ARRAY['podcast','newsletter','video'])[1 + (random()*2)::int],
       60 + (random()*1200)::int
FROM generate_series(1,20) g;
INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload)
SELECT c.id, uuid_generate_v4(),
       (ARRAY['play','pause','finish','click'])[1 + (random()*3)::int],
       now() - (random()*interval '5 minutes'),
       CASE WHEN random() < 0.7 THEN (random()*600000)::int ELSE NULL END,
       (ARRAY['ios','android','web-chrome','web-safari'])[1 + (random()*3)::int],
       jsonb_build_object('v','1')
FROM content c, generate_series(1,200);
