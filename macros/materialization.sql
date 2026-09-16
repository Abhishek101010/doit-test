{#
    Materialisation switch for the billing models.

    These models are designed to be **incremental**: partitioned by date and
    rebuilt with `insert_overwrite` so only the partitions inside the lookback
    window are recomputed.

    The BigQuery *sandbox* (a project with no billing account attached) blocks
    every DML statement, and dbt's incremental strategies all issue MERGE or
    INSERT. Running incrementally there fails with:

        Billing has not been enabled for this project.
        DML queries are not allowed in the free tier.

    So when `bigquery_sandbox` is true the models fall back to `table`, which
    dbt builds with `create or replace table` - pure DDL, and therefore allowed.
    Partitioning and clustering are unaffected, and `is_incremental()` simply
    stays false, so the lookback filters render to nothing and every run is a
    full rebuild.

    Once billing is enabled on the project, set `bigquery_sandbox: false` in
    `dbt_project.yml` and the models become genuinely incremental again - no
    other change required.
#}
{% macro incremental_or_table() -%}
    {{ 'table' if var('bigquery_sandbox', false) else 'incremental' }}
{%- endmacro %}
