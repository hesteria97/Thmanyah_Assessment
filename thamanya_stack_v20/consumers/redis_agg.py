from kafka import KafkaConsumer
import redis, json, time, os, sys
KAFKA_BOOTSTRAP=os.getenv('KAFKA_BOOTSTRAP','redpanda:9092')
REDIS_HOST=os.getenv('REDIS_HOST','redis')
r=redis.Redis(host=REDIS_HOST,port=6379,db=0)
consumer=KafkaConsumer('thm.enriched.events',bootstrap_servers=KAFKA_BOOTSTRAP,group_id='redis-agg',enable_auto_commit=True,auto_offset_reset='earliest',value_deserializer=lambda v: json.loads(v.decode('utf-8')),client_id='redis-agg-consumer')
def score(et): return 1.0 if et in ('play','finish') else (0.2 if et=='click' else 0.0)
print("[redis-agg] starting; bootstrap=", KAFKA_BOOTSTRAP, file=sys.stderr, flush=True)
for msg in consumer:
    rec=msg.value; ev_id=rec.get('id'); cid=rec.get('content_id'); et=rec.get('event_type')
    if not cid or not ev_id: consumer.commit(); continue
    if r.setnx(f'seen:{ev_id}',1):
        r.expire(f'seen:{ev_id}',900); s=score(et)
        if s>0:
            mb=int(time.time()//60); z=f'thm:top:{mb}'; r.zincrby(z,s,cid); r.expire(z,660)
            keys=[f'thm:top:{i}' for i in range(mb-9, mb+1)]
            try: r.zunionstore('thm:top:10m', keys); r.expire('thm:top:10m',120)
            except Exception: pass
        print(f"[redis-agg] scored {cid} +{s} (event {ev_id}, {et})", file=sys.stderr, flush=True)
    consumer.commit()
