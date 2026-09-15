{#
    STAGING - cloud usage (incremental)

    Flattens every nested struct on the billing export (project, service,
    sku, location, usage, cost, savings) and lifts the most commonly used
    labels into their own columns. The `credits` and `labels` arrays keep
    their own staging models for full detail.

    Unlike the other staging models this one is not a view: at ~1.7m rows
    the struct extraction is expensive enough that re-computing it on every
    downstream query is wasteful. It is therefore materialised
    incrementally on `usage_date`, with a lookback window so restated days
    are re-processed and `unique_key = 'usage_id'` removes the overlap.
#}

{{
    config(
        materialized = 'incremental',
        schema = 'staging',
        unique_key = 'usage_id',
        incremental_strategy = 'delete+insert',
        tags = ['staging', 'cloud_usage', 'incremental']
    )
}}

with source as (

    select * from {{ ref('raw_cloud_usage') }}
    {{ incremental_date_filter('_usage_date', relation = this, target_column = 'usage_date') }}

),

renamed as (

    select
        usage_id,
        cast(usage_date as date)                                        as usage_date,
        cast(export_time as timestamp)                                  as exported_at,
        date_trunc('month', cast(usage_date as date))                   as usage_month,
        dayname(cast(usage_date as date))                               as usage_day_name,
        (dayofweek(cast(usage_date as date)) in (0, 6))                 as is_weekend,

        customer_id,
        billing_account_id,
        cloud_provider,

        -- project struct
        struct_extract(project, 'project_id')                           as project_id,
        struct_extract(project, 'project_name')                         as project_name,

        -- service struct
        struct_extract(service, 'service_id')                           as service_id,
        struct_extract(service, 'service_name')                         as service_name,
        struct_extract(service, 'service_category')                     as service_category,

        -- sku struct
        struct_extract(sku, 'sku_id')                                   as sku_id,
        struct_extract(sku, 'sku_description')                          as sku_description,
        struct_extract(sku, 'pricing_unit')                             as pricing_unit,
        cast(struct_extract(sku, 'list_unit_price_usd') as double)      as list_unit_price_usd,

        -- location struct
        struct_extract(location, 'region')                              as cloud_region,
        struct_extract(location, 'zone')                                as cloud_zone,

        -- usage struct
        cast(struct_extract("usage", 'quantity') as double)             as usage_quantity,
        struct_extract("usage", 'unit')                                 as usage_unit,

        -- cost struct
        cast(struct_extract(cost, 'list_cost_usd') as double)           as list_cost_usd,
        cast(struct_extract(cost, 'discount_usd') as double)            as discount_usd,
        cast(struct_extract(cost, 'net_cost_usd') as double)            as net_cost_usd,
        struct_extract(cost, 'currency')                                as cost_currency,

        -- savings struct
        struct_extract(savings, 'flexsave_eligible')                            as is_flexsave_eligible,
        cast(struct_extract(savings, 'flexsave_savings_usd') as double)         as flexsave_savings_usd,
        cast(struct_extract(savings, 'optimisation_savings_usd') as double)     as optimisation_savings_usd,

        -- labels lifted out of the nested {key, value} array
        {{ label_value('labels', 'env') }}                              as environment,
        {{ label_value('labels', 'team') }}                             as team,
        {{ label_value('labels', 'cost_centre') }}                      as cost_centre,
        {{ label_value('labels', 'app') }}                              as application,
        {{ labels_to_map('labels') }}                                   as labels_map,
        len(labels)                                                     as label_count,

        -- credits stay nested here, aggregated in the marts layer
        len(credits)                                                    as credit_count,
        coalesce(
            list_sum(list_transform(credits, c -> cast(c.amount_usd as double))),
            0.0
        )                                                               as credit_amount_usd,

        _loaded_at

    from source

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
