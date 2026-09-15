{#
    RAW - customers

    Lands `data/raw/customers.json` exactly as it arrives: nested structs
    (address, account_manager) and nested arrays (contacts, subscriptions,
    billing_accounts) are preserved. No renaming, no casting, no filtering.

    Small, fully-restated master data, so it is rebuilt on every run.
#}

{{
    config(
        materialized = 'table',
        schema = 'raw',
        tags = ['raw', 'customers']
    )
}}

select
    *,
    '{{ var("raw_data_path") }}/customers.json' as _source_file,
    cast(now() as timestamp) as _loaded_at
from {{ raw_json('customers') }}
