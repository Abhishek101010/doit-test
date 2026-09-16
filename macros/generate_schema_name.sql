{#
    Put every model in the single target dataset, ignoring the per-layer
    `schema=` set in each model's config():

        target.dataset = doit_demo
        schema = 'raw' | 'staging' | 'marts'  ->  doit_demo

    BigQuery dataset IDs are alphanumeric + underscore only (hyphens are
    rejected), hence `doit_demo`.

    The warehouse layer stays obvious from the model names themselves -
    `raw_*`, `stg_*`, then `dim_*` / `fct_*` / `agg_*` - so one dataset
    remains easy to read. The `schema=` configs are deliberately left in the
    models: restoring dataset-per-layer is then a one-line change here
    (`{{ default_schema }}_{{ custom_schema_name | trim }}`).

    Switching target (dev -> ci) moves the whole warehouse to another dataset
    without touching a single model.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ target.schema }}
{%- endmacro %}
