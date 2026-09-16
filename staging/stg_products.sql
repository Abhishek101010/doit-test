{#
    STAGING - products (one row per product)

    Flattens the `pricing` struct and keeps the supported providers list
    both as an array and as a readable comma separated string.
#}

{{
    config(
        materialized = 'view',
        schema = 'staging',
        tags = ['staging', 'products']
    )
}}

with source as (

    select * from {{ ref('raw_products') }}

),

renamed as (

    select
        p.product_id,
        p.product_name,
        p.product_family,
        p.description                                       as product_description,
        p.is_active                                         as is_active_product,
        p.launch_date,

        p.supported_providers,
        array_to_string(p.supported_providers, ', ')        as supported_providers_list,
        array_length(p.supported_providers)                 as supported_provider_count,
        array_length(p.features)                            as feature_count,

        -- pricing struct
        p.pricing.model                                     as pricing_model,
        p.pricing.currency                                  as pricing_currency,
        p.pricing.base_fee_usd                              as base_fee_usd,
        array_length(p.pricing.tiers)                       as pricing_tier_count,

        p._loaded_at

    from source as p

)

select * from renamed
