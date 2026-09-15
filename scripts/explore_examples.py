"""Prints a set of example queries used to explain the data model.

Read-only; safe to run any time after a `dbt build`.
"""

import duckdb

c = duckdb.connect("doit_demo.duckdb", read_only=True)
c.execute("set max_expression_depth to 100")


def q(title: str, sql: str) -> None:
    """Print a result set as plain ASCII (DuckDB's box drawing breaks cp1252)."""
    rel = c.sql(sql)
    cols = rel.columns
    rows = rel.fetchall()
    widths = [
        max(len(str(col)), *(len(str(r[i])) for r in rows)) if rows else len(str(col))
        for i, col in enumerate(cols)
    ]
    line = "  ".join(str(col).ljust(widths[i]) for i, col in enumerate(cols))
    print(f"\n=== {title} ===")
    print(line)
    print("-" * len(line))
    for r in rows:
        print("  ".join(str(v).ljust(widths[i]) for i, v in enumerate(r)))

q("A. One usage row - what a billing line looks like", """
select usage_id, usage_date, customer_id, cloud_provider, service_name,
       sku_description, usage_quantity, usage_unit, list_cost_usd,
       discount_usd, net_cost_usd, credit_amount_usd, effective_cost_usd,
       environment, team, cost_centre
from staging.stg_cloud_usage
where usage_id = 'usg_00000000'
""")

q("B. Grain check - rows per day per account", """
select count(*) as total_rows,
       count(distinct usage_date) as days,
       count(distinct billing_account_id) as accounts,
       count(distinct service_id) as services,
       count(distinct sku_id) as skus
from staging.stg_cloud_usage
""")

q("C. Credits exploded (nested array -> rows)", """
select usage_id, credit_type, credit_amount_usd
from staging.stg_cloud_usage_credits
where usage_id = 'usg_00000000'
""")

q("D. Labels exploded (nested array -> rows)", """
select usage_id, label_key, label_value
from staging.stg_cloud_usage_labels
where usage_id = 'usg_00000000'
""")

q("E. Subscriptions - revenue side", """
select customer_id, subscription_id, product_id, subscription_tier,
       seats, mrr_usd, subscription_status, start_date, end_date
from staging.stg_subscriptions
order by customer_id
limit 8
""")

q("F. Spend vs revenue per customer per month", """
select customer_name, usage_month,
       round(effective_cost_usd) as cloud_spend,
       round(subscription_mrr_usd) as our_revenue,
       round(revenue_to_spend_ratio, 3) as rev_per_dollar_spend,
       round(total_savings_usd) as savings
from marts.agg_customer_monthly_spend
order by usage_month, cloud_spend desc
""")

q("G. Top cost drivers (which service burns the money)", """
select customer_name, usage_month, cloud_provider, service_name,
       round(effective_cost_usd) as spend,
       round(share_of_customer_month_spend * 100, 1) as pct_of_month,
       service_cost_rank
from marts.agg_service_monthly_spend
where service_cost_rank <= 3 and usage_month = '2024-05-01'
order by customer_name, service_cost_rank
limit 12
""")

q("H. Anomaly detection - biggest daily spikes", """
select customer_name, cloud_provider, usage_date,
       round(effective_cost_usd) as spend,
       round(effective_cost_7d_avg_usd) as avg_7d,
       round(spend_vs_7d_avg_ratio, 2) as vs_avg,
       round(day_over_day_change_pct * 100, 1) as dod_pct
from marts.agg_customer_daily_spend
where spend_vs_7d_avg_ratio is not null
order by spend_vs_7d_avg_ratio desc
limit 8
""")

q("I. Cost allocation - how much spend has no cost centre", """
select cost_centre,
       round(sum(effective_cost_usd)) as spend,
       round(100.0 * sum(effective_cost_usd)
             / sum(sum(effective_cost_usd)) over (), 1) as pct
from marts.agg_cost_allocation_monthly
group by 1
order by spend desc
""")

q("J. Spend by environment", """
select environment, round(sum(effective_cost_usd)) as spend
from marts.agg_cost_allocation_monthly
group by 1 order by 2 desc
""")

q("K. Customer 360 (the dimension)", """
select customer_name, customer_segment, sales_region, customer_status,
       active_subscription_count, round(active_mrr_usd) as mrr,
       cloud_providers, is_multicloud
from marts.dim_customers
order by active_mrr_usd desc
""")
