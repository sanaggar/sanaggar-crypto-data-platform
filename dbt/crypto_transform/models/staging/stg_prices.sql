-- Staging model: Extract and type data from raw JSON
-- Data comes from CoinGecko /coins/markets endpoint

with source as (
    select * from {{ source('raw', 'crypto_prices') }}
),

transformed as (
    select
        id,
        coin_id,
        (data->>'symbol')::varchar as symbol,
        (data->>'name')::varchar as name,
        (data->>'current_price')::numeric as price_usd,
        (data->>'market_cap')::numeric as market_cap_usd,
        (data->>'market_cap_rank')::integer as market_cap_rank,
        (data->>'total_volume')::numeric as volume_24h_usd,
        (data->>'price_change_percentage_24h')::numeric as change_24h_pct,
        (data->>'high_24h')::numeric as high_24h_usd,
        (data->>'low_24h')::numeric as low_24h_usd,
        (data->>'circulating_supply')::numeric as circulating_supply,
        (data->>'total_supply')::numeric as total_supply,
        (data->>'last_updated')::timestamp as price_updated_at,
        ingested_at
    from source
)

select * from transformed
