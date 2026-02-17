-- Staging model: Extract and type data from raw JSON

with source as (
    select * from {{ source('raw', 'crypto_prices') }}
),

transformed as (
    select
        id,
        coin_id,
        (data->>'usd')::numeric as price_usd,
        (data->>'eur')::numeric as price_eur,
        (data->>'usd_market_cap')::numeric as market_cap_usd,
        (data->>'eur_market_cap')::numeric as market_cap_eur,
        (data->>'usd_24h_vol')::numeric as volume_24h_usd,
        (data->>'eur_24h_vol')::numeric as volume_24h_eur,
        (data->>'usd_24h_change')::numeric as change_24h_pct,
        to_timestamp((data->>'last_updated_at')::bigint) as price_updated_at,
        ingested_at
    from source
)

select * from transformed
