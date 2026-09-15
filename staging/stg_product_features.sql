{#
    STAGING - product features (one row per product / feature)

    Explodes the nested `features` array on the raw product record.
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
        features
    from {{ ref('raw_products') }}

),

exploded as (

    select
        s.product_id,
        f as feature
    from source as s
    cross join unnest(s.features) as f

),

renamed as (

    select
        product_id,
        feature.feature_code            as feature_code,
        feature.feature_name            as feature_name,
        feature.availability            as availability_status,
        feature.min_tier                as minimum_tier,
        (feature.availability = 'GA')   as is_generally_available
    from exploded

)

select * from renamed
