{#
    Standard incremental predicate for the date-partitioned billing models.

    On a first run (or after `--full-refresh`) `is_incremental()` is false and
    the macro renders nothing, so the whole history is loaded. On later runs
    it keeps only rows on or after
    `max(<target_column>) - incremental_lookback_days`, which re-processes a
    small window of recent days so late-arriving or restated usage lines are
    picked up again.

    On BigQuery the models pair this with `incremental_strategy =
    'insert_overwrite'` and a date partition, so the partitions covered by the
    lookback window are replaced wholesale rather than merged row by row.

    Arguments
    ---------
    date_column     Date expression on the *incoming* rows.
    relation        Relation holding the high-water mark (defaults to `this`).
    target_column   Column holding the date in that relation (defaults to
                    `date_column`) - needed when the source and the model use
                    different names.
    operator        `where` (default) or `and`, so the predicate can be appended
                    to a query that already has a WHERE clause.

    Usage
    -----
        select * from {{ ref('raw_cloud_usage') }}
        {{ incremental_date_filter('usage_date') }}
#}
{% macro incremental_date_filter(date_column, relation=none, target_column=none, operator='where') -%}
    {%- set target_relation = relation if relation is not none else this -%}
    {%- set high_water_column = target_column if target_column is not none else date_column -%}
    {%- if is_incremental() and not var('full_refresh_usage', false) %}
        {{ operator }} {{ date_column }} >= (
            select coalesce(
                date_sub(
                    max({{ high_water_column }}),
                    interval {{ var("incremental_lookback_days", 3) }} day
                ),
                date '1900-01-01'
            )
            from {{ target_relation }}
        )
    {%- endif -%}
{%- endmacro %}


{#
    Same idea for models that are rebuilt a whole month at a time
    (month-partitioned `insert_overwrite` keyed on `usage_month`). The
    high-water month is pulled back by the lookback window first, so the month
    that is still being accumulated is always fully recomputed.
#}
{% macro incremental_month_filter(month_column, relation=none, target_column=none, operator='where') -%}
    {%- set target_relation = relation if relation is not none else this -%}
    {%- set high_water_column = target_column if target_column is not none else month_column -%}
    {%- if is_incremental() and not var('full_refresh_usage', false) %}
        {{ operator }} {{ month_column }} >= (
            select coalesce(
                date_trunc(
                    date_sub(
                        max({{ high_water_column }}),
                        interval {{ var("incremental_lookback_days", 3) }} day
                    ),
                    month
                ),
                date '1900-01-01'
            )
            from {{ target_relation }}
        )
    {%- endif -%}
{%- endmacro %}
