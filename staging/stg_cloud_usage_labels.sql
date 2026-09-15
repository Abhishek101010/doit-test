{#
    STAGING - cloud usage labels (one row per usage line / label)

    Explodes the nested `labels` array into a tall key/value table so any
    label - not just the ones promoted to columns in `stg_cloud_usage` -
    can be used for cost allocation.

    Partitioned and incremental on `usage_date`, overwriting whole days for
    the same reason as the credits model.
#}

{{
    config(
        materialized = incremental_or_table(),
        schema = 'staging',
        incremental_strategy = 'insert_overwrite',
        partition_by = {
            'field': 'usage_date',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by = ['customer_id', 'label_key'],
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
    where array_length(labels) > 0
    {{ incremental_date_filter('usage_date', relation = this, target_column = 'usage_date', operator = 'and') }}

),

exploded as (

    select
        s.usage_id,
        s.usage_date,
        s.customer_id,
        l as label
    from source as s
    cross join unnest(s.labels) as l

),

renamed as (

    select
        usage_id,
        usage_date,
        customer_id,
        label.key       as label_key,
        label.value     as label_value
    from exploded

)

select * from renamed
