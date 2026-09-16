{#
    STAGING - cloud usage (incremental)

    Flattens every nested struct on the billing export (project, service,
    sku, location, usage, cost, savings) and lifts the most commonly used
    labels into their own columns. The `credits` and `labels` arrays keep
    their own staging models for full detail.

    Unlike the other staging models this one is not a view: the struct
    extraction and the correlated label lookups are expensive enough that
    re-computing them on every downstream query is wasteful. It is therefore
    materialised incrementally, partitioned by `usage_date`, so a normal run
    only re-processes - and then overwrites - the partitions inside the
    lookback window.
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
        cluster_by = ['customer_id', 'cloud_provider'],
        tags = ['staging', 'cloud_usage', 'incremental']
    )
}}

with source as (

    select * from {{ ref('raw_cloud_usage') }}
    {{ incremental_date_filter('usage_date', relation = this, target_column = 'usage_date') }}

),

renamed as (

    select
        u.usage_id,
        u.usage_date,
        u.export_time                                   as exported_at,
        date_trunc(u.usage_date, month)                 as usage_month,
        format_date('%A', u.usage_date)                 as usage_day_name,
        (extract(dayofweek from u.usage_date) in (1, 7)) as is_weekend,

        u.customer_id,
        u.billing_account_id,
        u.cloud_provider,

        -- project struct
        u.project.project_id                            as project_id,
        u.project.project_name                          as project_name,

        -- service struct
        u.service.service_id                            as service_id,
        u.service.service_name                          as service_name,
        u.service.service_category                      as service_category,

        -- sku struct
        u.sku.sku_id                                    as sku_id,
        u.sku.sku_description                           as sku_description,
        u.sku.pricing_unit                              as pricing_unit,
        u.sku.list_unit_price_usd                       as list_unit_price_usd,

        -- location struct
        u.location.region                               as cloud_region,
        u.location.zone                                 as cloud_zone,

        -- usage struct
        u.usage.quantity                                as usage_quantity,
        u.usage.unit                                    as usage_unit,

        -- cost struct
        u.cost.list_cost_usd                            as list_cost_usd,
        u.cost.discount_usd                             as discount_usd,
        u.cost.net_cost_usd                             as net_cost_usd,
        u.cost.currency                                 as cost_currency,

        -- savings struct
        u.savings.flexsave_eligible                     as is_flexsave_eligible,
        u.savings.flexsave_savings_usd                  as flexsave_savings_usd,
        u.savings.optimisation_savings_usd              as optimisation_savings_usd,

        -- labels lifted out of the nested {key, value} array
        {{ label_value('u.labels', 'env') }}            as environment,
        {{ label_value('u.labels', 'team') }}           as team,
        {{ label_value('u.labels', 'cost_centre') }}    as cost_centre,
        {{ label_value('u.labels', 'app') }}            as application,
        -- BigQuery has no MAP type, so the full label set stays as a
        -- repeated STRUCT for ad-hoc UNNEST lookups downstream
        u.labels                                        as labels,
        array_length(u.labels)                          as label_count,

        -- credits stay nested here, aggregated in the marts layer
        array_length(u.credits)                         as credit_count,
        {{ array_sum('u.credits', 'amount_usd') }}      as credit_amount_usd,

        u._loaded_at

    from source as u

),

final as (

    select
        *,
        net_cost_usd + credit_amount_usd                                as effective_cost_usd,
        flexsave_savings_usd + optimisation_savings_usd                 as total_savings_usd,
        case
            when list_cost_usd > 0 then discount_usd / list_cost_usd
        end                                                             as discount_rate
    from renamed

)

select * from final
