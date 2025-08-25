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

نهاية الملف.

