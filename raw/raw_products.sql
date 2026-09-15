{#
    RAW - products

    Lands the `doit_demo.products` export as-is, including the nested
    `pricing` struct (with its `tiers` array), the `features` array and the
    `supported_providers` list.

    Small, fully-restated master data, so it is rebuilt on every run.
#}

{{
    config(
        materialized = 'table',
        schema = 'raw',
        tags = ['raw', 'products']
    )
}}

select
    *,
    'doit_demo.products' as _source_table,
    current_timestamp() as _loaded_at
from {{ source('landing', 'products') }}
