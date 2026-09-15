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
        product_id,
        unnest(features) as feature
    from source

),

renamed as (

    select
        product_id,
        struct_extract(feature, 'feature_code')      as feature_code,
        struct_extract(feature, 'feature_name')      as feature_name,
        struct_extract(feature, 'availability')      as availability_status,
        struct_extract(feature, 'min_tier')          as minimum_tier,
        (struct_extract(feature, 'availability') = 'GA')  as is_generally_available
    from exploded

)

select * from renamed
