"""
DAG for ingesting cryptocurrency data from CoinGecko API.
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
COINS = ["bitcoin", "ethereum", "solana", "cardano", "polkadot"]
POSTGRES_CONN_ID = "postgres_crypto"

default_args = {
    "owner": "sanaggar",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
}


def fetch_crypto_prices(**context):
    """Fetch current prices from CoinGecko API."""
    logging.info(f"Fetching prices for coins: {COINS}")
    
    # Build API URL
    coins_param = ",".join(COINS)
    url = f"{COINGECKO_API_URL}/simple/price"
    params = {
        "ids": coins_param,
        "vs_currencies": "usd,eur",
        "include_market_cap": "true",
        "include_24hr_vol": "true",
        "include_24hr_change": "true",
        "include_last_updated_at": "true",
    }
    
    # Make request
    response = requests.get(url, params=params, timeout=30)
    response.raise_for_status()
    data = response.json()
    
    logging.info(f"Successfully fetched data for {len(data)} coins")
    
    # Push to XCom for next task
    context["ti"].xcom_push(key="crypto_data", value=data)
    
    return data


def insert_to_database(**context):
    """Insert fetched data into PostgreSQL raw schema."""
    # Pull data from previous task
    ti = context["ti"]
    crypto_data = ti.xcom_pull(key="crypto_data", task_ids="fetch_prices")
    
    if not crypto_data:
        raise ValueError("No data received from fetch_prices task")
    
    # Get PostgreSQL connection
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN_ID)
    conn = hook.get_conn()
    cursor = conn.cursor()
    
    # Insert each coin's data
    inserted_count = 0
    for coin_id, coin_data in crypto_data.items():
        insert_sql = """
            INSERT INTO raw.crypto_prices (coin_id, data)
            VALUES (%s, %s)
        """
        cursor.execute(insert_sql, (coin_id, json.dumps(coin_data)))
        inserted_count += 1
    
    conn.commit()
    cursor.close()
    conn.close()
    
    logging.info(f"Successfully inserted {inserted_count} records into raw.crypto_prices")
    
    # Push count to XCom
    ti.xcom_push(key="inserted_count", value=inserted_count)
    
    return inserted_count


def log_success(**context):
    """Log successful completion of the pipeline."""
    ti = context["ti"]
    inserted_count = ti.xcom_pull(key="inserted_count", task_ids="insert_to_db")
    
    logging.info(f"Pipeline completed successfully!")
    logging.info(f"Total records inserted: {inserted_count}")


# Define the DAG
with DAG(
    dag_id="crypto_ingestion",
    default_args=default_args,
    description="Ingest cryptocurrency prices from CoinGecko API",
    schedule="@hourly",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["crypto", "ingestion", "coingecko"],
) as dag:
    
    # Task 1: Fetch prices from API
    fetch_prices = PythonOperator(
        task_id="fetch_prices",
        python_callable=fetch_crypto_prices,
    )
    
    # Task 2: Insert into database
    insert_to_db = PythonOperator(
        task_id="insert_to_db",
        python_callable=insert_to_database,
    )
    
    # Task 3: Log success
    log_success_task = PythonOperator(
        task_id="log_success",
        python_callable=log_success,
    )
    
    # Define task dependencies
    fetch_prices >> insert_to_db >> log_success_task
