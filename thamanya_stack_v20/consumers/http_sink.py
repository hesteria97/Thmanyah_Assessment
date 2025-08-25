from kafka import KafkaConsumer
import redis, json, time, os, requests
KAFKA_BOOTSTRAP=os.getenv('KAFKA_BOOTSTRAP','redpanda:9092')
REDIS_HOST=os.getenv('REDIS_HOST','redis')
ENDPOINT=os.getenv('EXTERNAL_ENDPOINT','http://external-api:8088/events')
r=redis.Redis(host=REDIS_HOST,port=6379,db=0)
consumer=KafkaConsumer('thm.enriched.events',bootstrap_servers=KAFKA_BOOTSTRAP,group_id='http-sink',enable_auto_commit=True,auto_offset_reset='earliest',value_deserializer=lambda v: json.loads(v.decode('utf-8')),client_id='http-sink-consumer')
for msg in consumer:
    rec=msg.value; ev_id=rec.get('id')
    if not ev_id: consumer.commit(); continue
    key=f'ext:seen:{ev_id}'
    if r.setnx(key,1):
        r.expire(key,86400)
        for i in range(5):
            try: requests.post(ENDPOINT,json=rec,timeout=3); break
            except Exception: time.sleep(min(30,2**i))
    consumer.commit()
