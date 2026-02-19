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


def fetch_and_store_crypto_prices(**context):
    """Fetch top 100 cryptocurrencies from CoinGecko and insert into PostgreSQL.

    Fetch and insert are combined in a single task to avoid pushing large
    payloads (100 coins) through XCom, which can exceed the metadata DB
    size limit and cause silent failures.
    """
    logging.info(f"Fetching top {TOP_N_COINS} cryptocurrencies by market cap")

    url = f"{COINGECKO_API_URL}/coins/markets"
    all_data = []

    per_page = 50
    for page in range(1, (TOP_N_COINS // per_page) + 1):
        params = {
            "vs_currency": "usd",
            "order": "market_cap_desc",
            "per_page": per_page,
            "page": page,
            "sparkline": False,
            "price_change_percentage": "24h",
        }
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        all_data.extend(response.json())
        logging.info(f"Fetched page {page} ({len(all_data)} coins so far)")

    logging.info(f"Successfully fetched data for {len(all_data)} coins")
    logging.info(f"Top 5: {[coin['id'] for coin in all_data[:5]]}")

    # Insert into PostgreSQL
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN_ID)
    conn = hook.get_conn()
    cursor = conn.cursor()

    insert_query = """
        INSERT INTO raw.crypto_prices (coin_id, data, ingested_at)
        VALUES (%s, %s, NOW())
    """

    try:
        for coin in all_data:
            cursor.execute(insert_query, (coin["id"], json.dumps(coin)))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()

    inserted_count = len(all_data)
    logging.info(f"Successfully inserted {inserted_count} records")

    # Push only the count via XCom (lightweight) for downstream logging
    context["ti"].xcom_push(key="inserted_count", value=inserted_count)
    return inserted_count


def log_success(**context):
    """Log successful completion of the DAG."""
    ti = context["ti"]
    inserted_count = ti.xcom_pull(
        key="inserted_count", task_ids="fetch_and_store"
    )
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

    fetch_and_store = PythonOperator(
        task_id="fetch_and_store",
        python_callable=fetch_and_store_crypto_prices,
    )

    log_success_task = PythonOperator(
        task_id="log_success",
        python_callable=log_success,
    )

    fetch_and_store >> log_success_task
