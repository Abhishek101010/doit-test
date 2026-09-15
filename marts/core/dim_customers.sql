{#
    MART · core - customer dimension

    Conformed customer entity: descriptive attributes from the master
    record enriched with subscription revenue and cloud footprint.
#}

{{
    config(
        materialized = 'table',
        schema = 'marts',
        tags = ['marts', 'core']
    )
}}

with customers as (

    select * from {{ ref('stg_customers') }}

),

subscriptions as (

    select
        customer_id,
        count(*)                                                    as subscription_count,
        count(*) filter (where is_active)                            as active_subscription_count,
        sum(mrr_usd) filter (where is_active)                        as active_mrr_usd,
        sum(arr_usd) filter (where is_active)                        as active_arr_usd,
        min(start_date)                                              as first_subscription_date
    from {{ ref('stg_subscriptions') }}
    group by 1

),

billing_accounts as (

    select
        customer_id,
        count(*)                                                     as billing_account_count,
        count(distinct cloud_provider)                               as cloud_provider_count,
        array_to_string(list_sort(list(distinct cloud_provider)), ', ') as cloud_providers,
        min(activated_on)                                            as first_account_activated_on
    from {{ ref('stg_billing_accounts') }}
    group by 1

),

primary_contact as (

    select
        customer_id,
        max(contact_name)   as primary_contact_name,
        max(contact_email)  as primary_contact_email
    from {{ ref('stg_customer_contacts') }}
    where is_primary_contact
    group by 1

),

final as (

    select
        c.customer_id,
        c.customer_name,
        c.customer_status,
        c.customer_segment,
        c.industry,
        c.sales_region,
        c.address_country,
        c.address_country_code,
        c.address_city,

        c.account_manager_id,
        c.account_manager_name,
        c.account_manager_email,

        pc.primary_contact_name,
        pc.primary_contact_email,
        c.contact_count,

        coalesce(s.subscription_count, 0)               as subscription_count,
        coalesce(s.active_subscription_count, 0)        as active_subscription_count,
        coalesce(s.active_mrr_usd, 0)                   as active_mrr_usd,
        coalesce(s.active_arr_usd, 0)                   as active_arr_usd,
        s.first_subscription_date,

        coalesce(ba.billing_account_count, 0)           as billing_account_count,
        coalesce(ba.cloud_provider_count, 0)            as cloud_provider_count,
        ba.cloud_providers,
        (coalesce(ba.cloud_provider_count, 0) > 1)      as is_multicloud,
        ba.first_account_activated_on,

        c.customer_created_at,
        c.customer_created_date,
        datediff('month', c.customer_created_date, current_date) as customer_tenure_months

    from customers c
    left join subscriptions s   on s.customer_id = c.customer_id
    left join billing_accounts ba on ba.customer_id = c.customer_id
    left join primary_contact pc on pc.customer_id = c.customer_id

)

select * from final
