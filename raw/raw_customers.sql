{#
    RAW - customers

    Lands the `doit_demo.customers` export exactly as it arrives:
    nested structs (address, account_manager) and nested arrays (contacts,
    subscriptions, billing_accounts) are preserved. No renaming, no casting,
    no filtering.

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
    'doit_demo.customers' as _source_table,
    current_timestamp() as _loaded_at
from {{ source('landing', 'customers') }}
