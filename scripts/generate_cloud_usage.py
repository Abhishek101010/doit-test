"""
Generates the nested `cloud_usage.json` file that feeds the RAW layer.

The shape intentionally mimics a cloud billing export (GCP/AWS/Azure) as it
would land in a FinOps platform such as DoiT: every row is one day of usage
for one SKU, with nested structs (service, sku, location, usage, cost,
savings) and nested arrays (credits, labels).

Deterministic *shape*: a fixed seed means re-running produces the same volumes,
costs and labels, so the dbt tests stay stable.

The date window is a rolling one ending today, because the target BigQuery
project runs in the free sandbox tier, which force-expires any table partition
older than 60 days. Generating a fixed historical window (e.g. 2024) would mean
every partition was deleted the instant dbt wrote it. Pass `--days` to change
the window length, or `--end-date` to pin it for a reproducible build.

Usage:
    python scripts/generate_cloud_usage.py
    python scripts/generate_cloud_usage.py --days 45 --end-date 2026-09-15
"""

from __future__ import annotations

import argparse
import json
import random
from datetime import date, timedelta
from pathlib import Path

SEED = 20240501

# BigQuery sandbox expires partitions older than 60 days; stay inside that.
DEFAULT_WINDOW_DAYS = 55

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
CUSTOMERS_FILE = RAW_DIR / "customers.json"
OUTPUT_FILE = RAW_DIR / "cloud_usage.json"

# --------------------------------------------------------------------------
# Catalogues, keyed by cloud provider
# --------------------------------------------------------------------------

SERVICES: dict[str, list[dict]] = {
    "GCP": [
        {
            "service_id": "svc_gcp_compute",
            "service_name": "Compute Engine",
            "service_category": "Compute",
            "skus": [
                ("sku_gcp_n2_core", "N2 Instance Core running", "hour", 0.0316, 60, 900),
                ("sku_gcp_n2_ram", "N2 Instance Ram running", "gibibyte hour", 0.0042, 200, 3600),
                ("sku_gcp_pd_ssd", "SSD backed PD Capacity", "gibibyte month", 0.170, 40, 400),
            ],
        },
        {
            "service_id": "svc_gcp_bigquery",
            "service_name": "BigQuery",
            "service_category": "Analytics",
            "skus": [
                ("sku_gcp_bq_analysis", "Analysis Slots Attribution", "slot hour", 0.048, 20, 700),
                ("sku_gcp_bq_storage", "Active Logical Storage", "gibibyte month", 0.020, 500, 9000),
            ],
        },
        {
            "service_id": "svc_gcp_gke",
            "service_name": "Kubernetes Engine",
            "service_category": "Containers",
            "skus": [
                ("sku_gcp_gke_mgmt", "Autopilot Cluster Management Fee", "hour", 0.10, 24, 240),
            ],
        },
        {
            "service_id": "svc_gcp_storage",
            "service_name": "Cloud Storage",
            "service_category": "Storage",
            "skus": [
                ("sku_gcp_gcs_std", "Standard Storage", "gibibyte month", 0.020, 300, 7000),
                ("sku_gcp_gcs_egress", "Network Internet Egress", "gibibyte", 0.120, 10, 900),
            ],
        },
    ],
    "AWS": [
        {
            "service_id": "svc_aws_ec2",
            "service_name": "Amazon Elastic Compute Cloud",
            "service_category": "Compute",
            "skus": [
                ("sku_aws_m6i_large", "m6i.large On Demand Linux", "hour", 0.096, 50, 1100),
                ("sku_aws_ebs_gp3", "EBS gp3 Provisioned Storage", "gibibyte month", 0.080, 50, 800),
                ("sku_aws_natgw", "NAT Gateway Hours", "hour", 0.045, 24, 300),
            ],
        },
        {
            "service_id": "svc_aws_s3",
            "service_name": "Amazon Simple Storage Service",
            "service_category": "Storage",
            "skus": [
                ("sku_aws_s3_std", "S3 Standard Storage", "gibibyte month", 0.023, 400, 9500),
                ("sku_aws_s3_req", "S3 PUT/GET Requests", "request", 0.0000004, 100000, 4000000),
            ],
        },
        {
            "service_id": "svc_aws_rds",
            "service_name": "Amazon Relational Database Service",
            "service_category": "Databases",
            "skus": [
                ("sku_aws_rds_r6g", "db.r6g.xlarge Multi-AZ PostgreSQL", "hour", 0.58, 24, 190),
            ],
        },
        {
            "service_id": "svc_aws_eks",
            "service_name": "Amazon Elastic Kubernetes Service",
            "service_category": "Containers",
            "skus": [
                ("sku_aws_eks_ctl", "EKS Cluster Control Plane", "hour", 0.10, 24, 168),
            ],
        },
    ],
    "Azure": [
        {
            "service_id": "svc_az_vm",
            "service_name": "Virtual Machines",
            "service_category": "Compute",
            "skus": [
                ("sku_az_d4s_v5", "D4s v5 Linux Compute Hours", "hour", 0.192, 24, 620),
                ("sku_az_disk_p30", "Premium SSD Managed Disks P30", "disk month", 0.135, 10, 90),
            ],
        },
        {
            "service_id": "svc_az_storage",
            "service_name": "Storage Accounts",
            "service_category": "Storage",
            "skus": [
                ("sku_az_blob_hot", "Hot Block Blob Data Stored", "gibibyte month", 0.021, 200, 5200),
            ],
        },
    ],
}

REGIONS: dict[str, list[tuple[str, str]]] = {
    "GCP": [("europe-west2", "europe-west2-a"), ("us-central1", "us-central1-b"), ("australia-southeast1", "australia-southeast1-c"), ("asia-northeast1", "asia-northeast1-a")],
    "AWS": [("eu-west-1", "eu-west-1a"), ("us-east-1", "us-east-1c"), ("sa-east-1", "sa-east-1a"), ("ap-northeast-1", "ap-northeast-1d")],
    "Azure": [("australiaeast", "australiaeast-1"), ("japaneast", "japaneast-2")],
}

ENVIRONMENTS = ["prod", "staging", "dev"]
TEAMS = ["platform", "data", "web", "ml", "security"]
COST_CENTRES = ["cc-1001", "cc-1002", "cc-2100", "cc-3300"]

CREDIT_TYPES = [
    ("committed_use_discount", 0.12),
    ("sustained_use_discount", 0.06),
    ("promotional_credit", 0.03),
    ("reseller_discount", 0.05),
]


def round2(value: float) -> float:
    return float(round(value, 2))


def build_usage_rows(start_date: date, end_date: date) -> list[dict]:
    rng = random.Random(SEED)
    customers = json.loads(CUSTOMERS_FILE.read_text(encoding="utf-8"))

    rows: list[dict] = []
    row_seq = 0

    for customer in customers:
        for account in customer["billing_accounts"]:
            provider = account["cloud_provider"]
            catalogue = SERVICES[provider]
            regions = REGIONS[provider]

            # Each billing account has a stable "shape": a home region, a
            # spend multiplier and the services it actually uses.
            home_region = rng.choice(regions)
            spend_factor = rng.uniform(0.4, 2.6)
            used_services = rng.sample(catalogue, k=min(len(catalogue), rng.randint(2, len(catalogue))))

            day = start_date
            while day <= end_date:
                # Weekends are quieter, and there is a gentle growth trend.
                weekend_factor = 0.72 if day.weekday() >= 5 else 1.0
                trend_factor = 1.0 + ((day - start_date).days / 400.0)

                for service in used_services:
                    for sku_id, sku_desc, unit, unit_price, qty_min, qty_max in service["skus"]:
                        if rng.random() < 0.06:
                            continue  # occasional day with no usage for this SKU

                        region, zone = home_region if rng.random() < 0.85 else rng.choice(regions)

                        quantity = rng.uniform(qty_min, qty_max) * spend_factor * weekend_factor * trend_factor
                        list_cost = quantity * unit_price

                        # Simulate a cost spike so anomaly metrics have signal.
                        if rng.random() < 0.008:
                            list_cost *= rng.uniform(2.5, 4.5)
                            quantity *= 3.0

                        discount = list_cost * rng.uniform(0.0, 0.18)
                        net_cost = list_cost - discount

                        credits = []
                        for credit_type, share in CREDIT_TYPES:
                            if rng.random() < 0.28:
                                credits.append(
                                    {
                                        "credit_type": credit_type,
                                        "credit_id": f"crd_{credit_type[:3]}_{row_seq:07d}",
                                        "amount_usd": round2(-net_cost * share * rng.uniform(0.4, 1.0)),
                                    }
                                )

                        labels = [
                            {"key": "env", "value": rng.choice(ENVIRONMENTS)},
                            {"key": "team", "value": rng.choice(TEAMS)},
                        ]
                        if rng.random() < 0.7:
                            labels.append({"key": "cost_centre", "value": rng.choice(COST_CENTRES)})
                        if rng.random() < 0.35:
                            labels.append({"key": "app", "value": f"app-{rng.randint(1, 12):02d}"})

                        is_compute = service["service_category"] == "Compute"
                        flexsave_eligible = is_compute and rng.random() < 0.8
                        flexsave_savings = round2(net_cost * rng.uniform(0.05, 0.22)) if flexsave_eligible else 0.0
                        optimisation_savings = round2(net_cost * rng.uniform(0.0, 0.09))

                        rows.append(
                            {
                                "usage_id": f"usg_{row_seq:08d}",
                                "usage_date": day.isoformat(),
                                "export_time": f"{day.isoformat()}T23:59:59Z",
                                "customer_id": customer["customer_id"],
                                "billing_account_id": account["billing_account_id"],
                                "cloud_provider": provider,
                                "project": {
                                    "project_id": f"{customer['customer_id'].replace('cus_', 'proj-')}-{rng.randint(1, 4)}",
                                    "project_name": f"{customer['customer_name'].split()[0].lower()}-{rng.choice(ENVIRONMENTS)}",
                                },
                                "service": {
                                    "service_id": service["service_id"],
                                    "service_name": service["service_name"],
                                    "service_category": service["service_category"],
                                },
                                "sku": {
                                    "sku_id": sku_id,
                                    "sku_description": sku_desc,
                                    "pricing_unit": unit,
                                    "list_unit_price_usd": unit_price,
                                },
                                "location": {
                                    "region": region,
                                    "zone": zone,
                                },
                                "usage": {
                                    "quantity": round(quantity, 4),
                                    "unit": unit,
                                },
                                "cost": {
                                    "list_cost_usd": round2(list_cost),
                                    "discount_usd": round2(discount),
                                    "net_cost_usd": round2(net_cost),
                                    "currency": "USD",
                                },
                                "savings": {
                                    "flexsave_eligible": flexsave_eligible,
                                    "flexsave_savings_usd": flexsave_savings,
                                    "optimisation_savings_usd": optimisation_savings,
                                },
                                "credits": credits,
                                "labels": labels,
                            }
                        )
                        row_seq += 1

                day += timedelta(days=1)

    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--days",
        type=int,
        default=DEFAULT_WINDOW_DAYS,
        help=f"Length of the usage window in days (default: {DEFAULT_WINDOW_DAYS}).",
    )
    parser.add_argument(
        "--end-date",
        type=date.fromisoformat,
        default=date.today(),
        help="Last day of the window, YYYY-MM-DD (default: today).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    end_date = args.end_date
    start_date = end_date - timedelta(days=args.days - 1)

    rows = build_usage_rows(start_date, end_date)
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(rows, handle, indent=2)
        handle.write("\n")
    print(f"Wrote {len(rows):,} usage rows for {start_date} .. {end_date} to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
