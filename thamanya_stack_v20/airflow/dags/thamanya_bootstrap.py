from datetime import datetime
from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.providers.http.operators.http import SimpleHttpOperator
from airflow.operators.python import PythonOperator
import requests, time
def wait_for_connect_clickhouse_plugin():
    url = "http://connect:8083/connector-plugins"
    for _ in range(60):
        try:
            r = requests.get(url, timeout=2)
            if r.ok and "com.clickhouse.kafka.connect.ClickHouseSinkConnector" in r.text:
                return
        except Exception:
            pass
        time.sleep(2)
    raise RuntimeError("ClickHouse sink plugin not visible in /connector-plugins")
with DAG(dag_id="thamanya_bootstrap", start_date=datetime(2024,1,1), schedule=None, catchup=False) as dag:
    start = EmptyOperator(task_id="start")
    ch_db = SimpleHttpOperator(task_id="clickhouse_create_db", http_conn_id="CLICKHOUSE_HTTP", method="POST", endpoint="/", data="CREATE DATABASE IF NOT EXISTS thm", headers={"Content-Type":"text/plain"})
    tbl_sql = open("/opt/airflow/dags/resources/clickhouse.create_table.sql","r",encoding="utf-8").read()
    ch_tbl = SimpleHttpOperator(task_id="clickhouse_create_table", http_conn_id="CLICKHOUSE_HTTP", method="POST", endpoint="/?database=thm", data=tbl_sql, headers={"Content-Type":"text/plain"})
    wait_plugin = PythonOperator(task_id="wait_for_clickhouse_sink_plugin", python_callable=wait_for_connect_clickhouse_plugin)
    src_json = open("/opt/airflow/dags/resources/pg-engagement-source.json","r",encoding="utf-8").read()
    connect_src = SimpleHttpOperator(task_id="register_debezium_source", http_conn_id="CONNECT_HTTP", method="POST", endpoint="/connectors", data=src_json, headers={"Content-Type":"application/json"})
    sink_json = open("/opt/airflow/dags/resources/clickhouse-sink.json","r",encoding="utf-8").read()
    connect_sink = SimpleHttpOperator(task_id="register_clickhouse_sink", http_conn_id="CONNECT_HTTP", method="POST", endpoint="/connectors", data=sink_json, headers={"Content-Type":"application/json"})
    end = EmptyOperator(task_id="end")
    start >> ch_db >> ch_tbl >> wait_plugin >> connect_src >> connect_sink >> end
