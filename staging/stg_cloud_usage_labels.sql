{#
    STAGING - cloud usage labels (one row per usage line / label)

    Explodes the nested `labels` array into a tall key/value table so any
    label - not just the ones promoted to columns in `stg_cloud_usage` -
    can be used for cost allocation.

    Incremental on `usage_date`, replacing whole days for the same reason
    as the credits model.
#}

{{
    config(
        materialized = 'incremental',
        schema = 'staging',
        unique_key = 'usage_date',
        incremental_strategy = 'delete+insert',
        tags = ['staging', 'cloud_usage', 'incremental']
    )
}}

with source as (

    select
        usage_id,
        usage_date,
        customer_id,
        labels
    from {{ ref('raw_cloud_usage') }}
    where len(labels) > 0
    {{ incremental_date_filter('_usage_date', relation = this, target_column = 'usage_date', operator = 'and') }}

),

exploded as (

    select
        usage_id,
        usage_date,
        customer_id,
        unnest(labels) as label
    from source

),

renamed as (

    select
        usage_id,
        cast(usage_date as date)                as usage_date,
        customer_id,
        struct_extract(label, 'key')            as label_key,
        struct_extract(label, 'value')          as label_value
    from exploded

)

select * from renamed
