{#
    RAW - cloud usage (incremental)

    Lands `doit_demo.cloud_usage`, the simulated multicloud billing
    export. One record = one day of usage for one SKU on one billing account,
    with nested structs (project, service, sku, location, usage, cost, savings)
    and nested arrays (credits, labels).

    Incremental strategy
    --------------------
    The table is partitioned by `usage_date` and uses BigQuery's
    `insert_overwrite` strategy. A normal run only reads the days at or after
    `max(usage_date) - incremental_lookback_days`, and dbt then replaces
    exactly those partitions - so restated / late-arriving lines overwrite the
    previous version of their day instead of duplicating it.
#}

{{
    config(
        materialized = incremental_or_table(),
        schema = 'raw',
        incremental_strategy = 'insert_overwrite',
        partition_by = {
            'field': 'usage_date',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by = ['customer_id', 'billing_account_id'],
        tags = ['raw', 'cloud_usage', 'incremental']
    )
}}

with source as (

    select
        *,
        'doit_demo.cloud_usage' as _source_table,
        current_timestamp() as _loaded_at
    from {{ source('landing', 'cloud_usage') }}

)

select *
from source
{{ incremental_date_filter('usage_date') }}
