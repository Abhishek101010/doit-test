"""
Load the landed raw JSON files into BigQuery.

The files in `data/raw/` are pretty-printed JSON *arrays* of nested objects,
which BigQuery cannot ingest directly. This script streams each file, rewrites
it as newline-delimited JSON (one object per line) in `target/ndjson/`, and
loads it into the `doit_demo` dataset with schema auto-detection so the
nested STRUCT / ARRAY shape is preserved.

These three landed tables (`customers`, `products`, `cloud_usage`) are the
external boundary of the project: dbt never writes to them, it only reads them
through the sources declared in `raw/_raw__sources.yml`. Everything dbt builds
alongside them is prefixed by layer - `raw_*`, `stg_*`, `dim_*` / `fct_*` /
`agg_*` - so the two never collide.

Run once (or whenever the source files change) before `dbt build`:

    python scripts/load_raw_to_bigquery.py

Authentication uses Application Default Credentials:

    gcloud auth application-default login --project=friendlychat-843d1
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from google.api_core.exceptions import NotFound
from google.cloud import bigquery

PROJECT_ID = "friendlychat-843d1"
LANDING_DATASET = "doit_demo"
LOCATION = "US"

PROJECT_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_DIR / "data" / "raw"
NDJSON_DIR = PROJECT_DIR / "target" / "ndjson"

# source file stem -> destination BigQuery table
TABLES = {
    "customers": "customers",
    "products": "products",
    "cloud_usage": "cloud_usage",
}


def to_ndjson(src: Path, dst: Path) -> int:
    """Rewrite a pretty-printed JSON array as newline-delimited JSON."""
    with src.open("r", encoding="utf-8") as fh:
        records = json.load(fh)

    if not isinstance(records, list):
        raise ValueError(f"{src.name} is not a JSON array")

    dst.parent.mkdir(parents=True, exist_ok=True)
    with dst.open("w", encoding="utf-8") as fh:
        for record in records:
            # ensure_ascii keeps the payload byte-safe for the BigQuery loader
            fh.write(json.dumps(record, ensure_ascii=False, default=str))
            fh.write("\n")

    return len(records)


def ensure_dataset(client: bigquery.Client) -> None:
    dataset_id = f"{PROJECT_ID}.{LANDING_DATASET}"
    try:
        client.get_dataset(dataset_id)
    except NotFound:
        dataset = bigquery.Dataset(dataset_id)
        dataset.location = LOCATION
        client.create_dataset(dataset)
        print(f"created dataset {dataset_id} in {LOCATION}")


def load_table(client: bigquery.Client, ndjson_path: Path, table_name: str) -> int:
    table_id = f"{PROJECT_ID}.{LANDING_DATASET}.{table_name}"

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=True,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        ignore_unknown_values=False,
    )

    with ndjson_path.open("rb") as fh:
        job = client.load_table_from_file(fh, table_id, job_config=job_config)
    job.result()  # block until the load completes

    return client.get_table(table_id).num_rows


def main() -> int:
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)
    ensure_dataset(client)

    for stem, table_name in TABLES.items():
        src = RAW_DIR / f"{stem}.json"
        if not src.exists():
            print(f"SKIP {stem}: {src} not found")
            continue

        ndjson_path = NDJSON_DIR / f"{stem}.ndjson"
        record_count = to_ndjson(src, ndjson_path)
        print(f"{stem}: converted {record_count:,} records -> {ndjson_path.name}")

        row_count = load_table(client, ndjson_path, table_name)
        print(f"{stem}: loaded {row_count:,} rows -> {LANDING_DATASET}.{table_name}")

    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
