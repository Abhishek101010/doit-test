{#
    RAW - products

    Lands `data/raw/products.json` as-is, including the nested `pricing`
    struct (with its `tiers` array), the `features` array and the
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
    '{{ var("raw_data_path") }}/products.json' as _source_file,
    cast(now() as timestamp) as _loaded_at
from {{ raw_json('products') }}
