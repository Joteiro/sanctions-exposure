"""Build docs/index.html: a static snapshot dashboard of the exposure marts.

Usage, from the repository root, with the .venv active:

    python scripts/build_dashboard.py

It queries the dbt marts in BigQuery (with the same Google credentials dbt uses),
embeds the results in scripts/dashboard_template.html and writes docs/index.html,
which GitHub Pages serves as is. The published page never queries BigQuery: it is
a snapshot, so it costs nothing to view and does not break when sandbox tables
expire. Re-run the script after rebuilding the marts to refresh it.

No address is exported: sanctioned addresses are numbered by listing date in SQL,
and counterparties leave the warehouse only as counts.
"""

import argparse
import datetime
import decimal
import json
import sys
from pathlib import Path

PROJECT = "sanctions-exposure"
DATASET = "dbt_dev"
LOCATION = "US"
# Date of the OpenSanctions export the seed was built from (scripts/extract_wallets.py).
SANCTIONS_EXPORT_DATE = "2026-11-04"
# Matches var('hub_degree_threshold') in dbt_project.yml: the slider's starting value.
DEFAULT_THRESHOLD = 1000

MiB = 1024 ** 2
GiB = 1024 ** 3

# (name, SQL, maximum bytes billed). Every query reads a mart table except
# active_addresses, which needs every transfer and reads the int_transfers view.
QUERIES = [
    ("window", f"""
        select format_date('%Y-%m-%d', min(date(block_timestamp))) as start,
               format_date('%Y-%m-%d', max(date(block_timestamp))) as `end`
        from `{PROJECT}.{DATASET}.stg_ethereum__transactions`
    """, 200 * MiB),
    ("exposure", f"""
        select
            count(*)                                    as exposure_rows,
            count(distinct transfer_id)                 as transfers,
            count(distinct sanctioned_address)          as sanctioned,
            count(distinct counterparty_address)        as counterparties,
            countif(asset = 'ETH')                      as eth_rows,
            countif(asset != 'ETH')                     as token_rows,
            round(coalesce(sum(value_eth), 0), 4)       as eth_value,
            countif(listing_status = 'listed_later')    as retroactive_rows,
            countif(listing_status = 'already_listed')  as already_listed_rows,
            countif(listing_status = 'unknown')         as unknown_rows
        from `{PROJECT}.{DATASET}.fct_sanctioned_exposure`
    """, 100 * MiB),
    ("cases", f"""
        with per_address as (
            select
                sanctioned_address,
                min(first_listed_at)            as first_listed_at,
                min(block_timestamp)            as first_transfer_at,
                max(block_timestamp)            as last_transfer_at,
                count(*)                        as exposure_rows,
                countif(asset = 'ETH')          as eth_rows,
                countif(asset != 'ETH')         as token_rows,
                countif(direction = 'sent')     as sent_rows,
                countif(direction = 'received') as received_rows
            from `{PROJECT}.{DATASET}.fct_sanctioned_exposure`
            group by sanctioned_address
        )
        select
            row_number() over (order by first_listed_at, sanctioned_address) as case_number,
            format_date('%Y-%m-%d', date(first_listed_at))   as first_listed,
            format_date('%Y-%m-%d', date(first_transfer_at)) as first_transfer,
            format_date('%Y-%m-%d', date(last_transfer_at))  as last_transfer,
            date_diff(date(first_listed_at), date(first_transfer_at), day) as days_from_transfer_to_listing,
            exposure_rows, eth_rows, token_rows, sent_rows, received_rows
        from per_address
        order by case_number
    """, 100 * MiB),
    ("hops", f"""
        select
            countif(hop_distance = 0)                              as hop0,
            countif(hop_distance = 0 and counterparties is null)   as hop0_inactive,
            countif(hop_distance = 1)                              as hop1,
            countif(hop_distance = 2)                              as hop2
        from `{PROJECT}.{DATASET}.fct_address_exposure_hops`
    """, 100 * MiB),
    ("direct_counterparties", f"""
        select counterparties
        from `{PROJECT}.{DATASET}.fct_address_exposure_hops`
        where hop_distance = 1
        order by counterparties desc
    """, 100 * MiB),
    ("curve", f"""
        select min_via_counterparties as min_via, count(*) as n
        from `{PROJECT}.{DATASET}.fct_address_exposure_hops`
        where hop_distance = 2
        group by min_via_counterparties
        order by min_via_counterparties
    """, 100 * MiB),
    ("active_addresses", f"""
        select count(distinct address) as active_addresses
        from (
            select from_address as address from `{PROJECT}.{DATASET}.int_transfers`
            union all
            select to_address from `{PROJECT}.{DATASET}.int_transfers`
        )
    """, 2 * GiB),
]


def plain(value):
    """Make BigQuery values JSON-serialisable."""
    if isinstance(value, decimal.Decimal):
        return float(value)
    if isinstance(value, (datetime.date, datetime.datetime)):
        return value.isoformat()
    return value


def fetch() -> dict:
    from google.cloud import bigquery  # installed with dbt-bigquery

    client = bigquery.Client(project=PROJECT, location=LOCATION)
    raw = {}
    for name, sql, max_bytes in QUERIES:
        config = bigquery.QueryJobConfig(maximum_bytes_billed=max_bytes)
        rows = client.query(sql, job_config=config).result()
        raw[name] = [{k: plain(v) for k, v in row.items()} for row in rows]
        print(f"  {name:<22} {len(raw[name]):>3} row(s)")
    return shape(raw)


def shape(raw: dict) -> dict:
    curve = raw["curve"]
    if any(p["min_via"] is None for p in curve):
        sys.exit("fct_address_exposure_hops has no min_via_counterparties values: "
                 "rebuild it with `dbt build --select fct_address_exposure_hops`.")
    return {
        "generated_at": datetime.date.today().isoformat(),
        "sanctions_export_date": SANCTIONS_EXPORT_DATE,
        "default_threshold": DEFAULT_THRESHOLD,
        "window": raw["window"][0],
        "exposure": raw["exposure"][0],
        "cases": raw["cases"],
        "hops": raw["hops"][0],
        "direct_counterparties": [r["counterparties"] for r in raw["direct_counterparties"]],
        "curve": curve,
        "active_addresses": raw["active_addresses"][0]["active_addresses"],
    }


def render(data: dict, template: Path, output: Path) -> None:
    html = template.read_text(encoding="utf-8")
    if "__DATA__" not in html:
        sys.exit(f"{template} has no __DATA__ placeholder.")
    # "</" is escaped so no value can close the <script> block that holds the data.
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html.replace("__DATA__", payload), encoding="utf-8", newline="\n")


def main() -> None:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--template", type=Path, default=here / "dashboard_template.html")
    parser.add_argument("--output", type=Path, default=here.parent / "docs" / "index.html")
    parser.add_argument("--data-json", type=Path,
                        help="render from a saved JSON file instead of querying BigQuery")
    parser.add_argument("--save-json", type=Path, help="also save the fetched data as JSON")
    args = parser.parse_args()

    if args.data_json:
        data = json.loads(args.data_json.read_text(encoding="utf-8"))
    else:
        print("Querying the marts in BigQuery:")
        data = fetch()
    if args.save_json:
        args.save_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    render(data, args.template, args.output)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
