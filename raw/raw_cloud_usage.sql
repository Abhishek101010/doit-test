{#
    RAW - cloud usage (incremental)

    Lands `data/raw/cloud_usage.json`, the simulated multicloud billing
    export. One record = one day of usage for one SKU on one billing
    account, with nested structs (project, service, sku, location, usage,
    cost, savings) and nested arrays (credits, labels).

    Incremental strategy
    --------------------
    The export grows by `usage_date`, so a normal run only keeps the days
    at or after `max(usage_date) - incremental_lookback_days`. The lookback
    window lets restated / late-arriving lines through and
    `unique_key = 'usage_id'` removes the resulting overlap.
#}

{{
    config(
        materialized = 'incremental',
        schema = 'raw',
        unique_key = 'usage_id',
        incremental_strategy = 'delete+insert',
        tags = ['raw', 'cloud_usage', 'incremental']
    )
}}

with source as (

    select
        *,
        -- typed copy of `usage_date`, used as the incremental partition key
        cast(usage_date as date) as _usage_date,
        '{{ var("raw_data_path") }}/cloud_usage.json' as _source_file,
        cast(now() as timestamp) as _loaded_at
    from {{ raw_json('cloud_usage') }}

)

select *
from source
{{ incremental_date_filter('_usage_date') }}
