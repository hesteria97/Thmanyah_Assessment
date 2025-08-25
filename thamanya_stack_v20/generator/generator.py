import os, time, uuid, random
import psycopg2
from psycopg2.extras import Json, register_uuid
def connect_with_retries():
    for _ in range(30):
        try:
            conn = psycopg2.connect(
                host=os.getenv("PGHOST","postgres"),
                port=os.getenv("PGPORT","5432"),
                dbname=os.getenv("PGDATABASE","thm"),
                user=os.getenv("PGUSER","app"),
                password=os.getenv("PGPASSWORD","app"),
            )
            register_uuid(conn_or_curs=conn)
            return conn
        except Exception:
            time.sleep(2)
    raise RuntimeError("Could not connect to Postgres after retries")
conn = connect_with_retries(); conn.autocommit = True; cur = conn.cursor()
def pick_content_id():
    cur.execute("SELECT id FROM content ORDER BY random() LIMIT 1"); r = cur.fetchone()
    if not r:
        cur.execute("INSERT INTO content(slug,title,content_type,length_seconds) VALUES (%s,%s,%s,%s) RETURNING id",
                    (f"auto-{uuid.uuid4().hex[:8]}", "Auto Content", random.choice(["podcast","newsletter","video"]), random.randint(60, 1800)))
        return cur.fetchone()[0]
    return r[0]
EVENTS = ["play","pause","finish","click"]; DEVICES = ["ios","android","web-chrome","web-safari"]
SQL = ("INSERT INTO engagement_events (content_id,user_id,event_type,event_ts,duration_ms,device,raw_payload) VALUES (%s,%s,%s, now(), %s, %s, %s)")
while True:
    cid = pick_content_id(); uid = uuid.uuid4(); et = random.choice(EVENTS)
    dur = None if et in ("click","pause") else random.randint(1000, 180000); dev = random.choice(DEVICES)
    cur.execute(SQL, (cid, uid, et, dur, dev, Json({"gen":"auto"}))); time.sleep(5)
