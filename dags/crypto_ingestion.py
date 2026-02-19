"""
DAG for ingesting cryptocurrency data from CoinGecko API.
Fetches top 100 cryptocurrencies by market cap.
Runs hourly and stores raw data in PostgreSQL.
"""

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from datetime import datetime, timedelta
import requests
import json
import logging

# Configuration
COINGECKO_API_URL = "https://api.coingecko.com/api/v3"
POSTGRES_CONN_ID = "postgres_crypto"
TOP_N_COINS = 100  # Number of top cryptocurrencies to fetch

default_args = {
    "owner": "sanaggar",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
}


def fetch_crypto_prices(**context):
    """Fetch top 100 cryptocurrencies from CoinGecko API."""
    logging.info(f"Fetching top {TOP_N_COINS} cryptocurrencies by market cap")
    
    url = f"{COINGECKO_API_URL}/coins/markets"
    params = {
        "vs_currency": "usd",
        "order": "market_cap_desc",
        "per_page": TOP_N_COINS,
        "page": 1,
        "sparkline": False,
        "price_change_percentage": "24h"
    }
    
    response = requests.get(url, params=params, timeout=30)
    response.raise_for_status()
    data = response.json()
    
    logging.info(f"Successfully fetched data for {len(data)} coins")
    logging.info(f"Top 5: {[coin['id'] for coin in data[:5]]}")
    
    context["ti"].xcom_push(key="crypto_data", value=data)
    return data


def insert_to_database(**context):
    """Insert fetched data into PostgreSQL raw schema."""
    ti = context["ti"]
    data = ti.xcom_pull(key="crypto_data", task_ids="fetch_prices")
    
    if not data:
        raise ValueError("No data received from fetch_prices task")
    
    logging.info(f"Inserting {len(data)} coins into database")
    
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN_ID)
    conn = hook.get_conn()
    cursor = conn.cursor()
    
    insert_query = """
        INSERT INTO raw.crypto_prices (coin_id, data, ingested_at)
        VALUES (%s, %s, NOW())
    """
    
    inserted_count = 0
    for coin in data:
        cursor.execute(insert_query, (coin["id"], json.dumps(coin)))
        inserted_count += 1
    
    conn.commit()
    cursor.close()
    conn.close()
    
    logging.info(f"Successfully inserted {inserted_count} records")
    return inserted_count


def log_success(**context):
    """Log successful completion of the DAG."""
    ti = context["ti"]
    inserted_count = ti.xcom_pull(task_ids="insert_to_db")
    logging.info(f"DAG completed successfully. Inserted {inserted_count} records.")


with DAG(
    dag_id="crypto_ingestion",
    default_args=default_args,
    description="Ingest top 100 cryptocurrency prices from CoinGecko",
    schedule="@hourly",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["coingecko", "crypto", "ingestion"],
) as dag:
    
    fetch_prices = PythonOperator(
        task_id="fetch_prices",
        python_callable=fetch_crypto_prices,
    )
    
    insert_to_db = PythonOperator(
        task_id="insert_to_db",
        python_callable=insert_to_database,
    )
    
    log_success_task = PythonOperator(
        task_id="log_success",
        python_callable=log_success,
    )
    
    fetch_prices >> insert_to_db >> log_success_task
