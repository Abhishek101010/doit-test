{#
    STAGING - customers (one row per customer)

    Flattens the `address` and `account_manager` structs, standardises
    naming and casts the timestamps. The nested arrays are exposed as
    counts here and flattened out into their own staging models.
#}

{{
    config(
        materialized = 'view',
        schema = 'staging',
        tags = ['staging', 'customers']
    )
}}

with source as (

    select * from {{ ref('raw_customers') }}

),

renamed as (

    select
        customer_id,
        customer_name,
        lower(status)                                   as customer_status,
        segment                                         as customer_segment,
        industry,

        -- address struct
        struct_extract(address, 'street')               as address_street,
        struct_extract(address, 'city')                 as address_city,
        struct_extract(address, 'country')              as address_country,
        struct_extract(address, 'country_code')         as address_country_code,
        struct_extract(address, 'region')               as sales_region,

        -- account manager struct
        struct_extract(account_manager, 'employee_id')  as account_manager_id,
        struct_extract(account_manager, 'name')         as account_manager_name,
        struct_extract(account_manager, 'email')        as account_manager_email,

        -- nested array cardinality
        len(contacts)                                   as contact_count,
        len(subscriptions)                              as subscription_count,
        len(billing_accounts)                           as billing_account_count,

        cast(created_at as timestamp)                   as customer_created_at,
        cast(created_at as date)                        as customer_created_date,
        _loaded_at

    from source

)

select * from renamed
