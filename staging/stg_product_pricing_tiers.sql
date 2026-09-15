{#
    STAGING - product pricing tiers (one row per product / tier)

    Explodes `pricing.tiers`, the doubly nested array on the raw product
    record (a struct that contains a list of structs).
#}

{{
    config(
        materialized = 'view',
        schema = 'staging',
        tags = ['staging', 'products']
    )
}}

with source as (

    select
        product_id,
        struct_extract(pricing, 'model')    as pricing_model,
        struct_extract(pricing, 'currency') as pricing_currency,
        struct_extract(pricing, 'tiers')    as tiers
    from {{ ref('raw_products') }}

),

exploded as (

    select
        product_id,
        pricing_model,
        pricing_currency,
        unnest(tiers) as tier
    from source

),

renamed as (

    select
        product_id,
        struct_extract(tier, 'tier_name')                                   as tier_name,
        pricing_model,
        pricing_currency,
        cast(struct_extract(tier, 'min_monthly_spend_usd') as double)       as min_monthly_spend_usd,
        cast(struct_extract(tier, 'max_monthly_spend_usd') as double)       as max_monthly_spend_usd,
        cast(struct_extract(tier, 'rate_pct') as double)                    as rate_pct,
        struct_extract(tier, 'included_support')                            as included_support
    from exploded

)

select * from renamed
