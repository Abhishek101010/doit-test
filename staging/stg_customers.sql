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
        c.customer_id,
        c.customer_name,
        lower(c.status)                     as customer_status,
        c.segment                           as customer_segment,
        c.industry,

        -- address struct
        c.address.street                    as address_street,
        c.address.city                      as address_city,
        c.address.country                   as address_country,
        c.address.country_code              as address_country_code,
        c.address.region                    as sales_region,

        -- account manager struct
        c.account_manager.employee_id       as account_manager_id,
        c.account_manager.name              as account_manager_name,
        c.account_manager.email             as account_manager_email,

        -- nested array cardinality
        array_length(c.contacts)            as contact_count,
        array_length(c.subscriptions)       as subscription_count,
        array_length(c.billing_accounts)    as billing_account_count,

        c.created_at                        as customer_created_at,
        date(c.created_at)                  as customer_created_date,
        c._loaded_at

    from source as c

)

select * from renamed
