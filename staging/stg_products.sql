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
        product_id,
        product_name,
        product_family,
        description                                                 as product_description,
        is_active                                                   as is_active_product,
        cast(launch_date as date)                                   as launch_date,

        supported_providers,
        array_to_string(supported_providers, ', ')                   as supported_providers_list,
        len(supported_providers)                                    as supported_provider_count,
        len(features)                                               as feature_count,

        -- pricing struct
        struct_extract(pricing, 'model')                            as pricing_model,
        struct_extract(pricing, 'currency')                         as pricing_currency,
        cast(struct_extract(pricing, 'base_fee_usd') as double)     as base_fee_usd,
        len(struct_extract(pricing, 'tiers'))                       as pricing_tier_count,

        _loaded_at

    from source

)

select * from renamed
