"""Extract Ethereum-format wallet addresses from an OpenSanctions FollowTheMoney export.

Usage, from the repository root:

    python scripts/extract_wallets.py
    python scripts/extract_wallets.py --input data/entities.ftm.json --output seeds/ofac_wallets.csv

Input:  the `entities.ftm.json` export of the US OFAC SDN dataset,
        https://www.opensanctions.org/datasets/us_ofac_sdn/ (one JSON entity per line).
Output: a CSV seed with one row per (wallet entity, address, holder).

Both files are git-ignored. OpenSanctions data is licensed CC BY-NC 4.0 and this
repository does not redistribute extracts: re-run this script to regenerate the seed.

Decisions encoded here:
- Filter on address FORMAT (0x + 40 hex characters), not on the currency label.
  The same Ethereum address can be listed under a token (USDT, USDC) or another
  EVM chain. The label is kept as a column, never used as a filter.
- Keep the address exactly as published, whitespace stripped. Normalising case is
  the staging model's job, so that its effect can be measured.
- No deduplication. When one address appears on several wallet entities, every
  row is kept. What to do about it is a modelling decision, made in staging.
"""

import argparse
import csv
import json
import re
import sys
from collections import Counter
from pathlib import Path

EVM_ADDRESS = re.compile(r"^0x[0-9a-fA-F]{40}$")
COLUMNS = ["wallet_id", "address", "currency", "holder_id", "first_seen"]


def extract(input_path: Path) -> tuple[int, list[dict]]:
    wallets = 0
    rows = []
    with input_path.open(encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                entity = json.loads(line)
            except json.JSONDecodeError as exc:
                sys.exit(f"{input_path}, line {line_no}: not valid JSON ({exc})")
            if entity.get("schema") != "CryptoWallet":
                continue
            wallets += 1
            props = entity.get("properties", {})
            # FollowTheMoney property values are always lists, even with one value.
            currencies = props.get("currency") or [""]
            holders = props.get("holder") or [""]
            for raw in props.get("publicKey", []):
                address = raw.strip()
                if not EVM_ADDRESS.match(address):
                    continue
                for currency in currencies:
                    for holder in holders:
                        rows.append({
                            "wallet_id": entity["id"],
                            "address": address,
                            "currency": currency,
                            "holder_id": holder,
                            "first_seen": entity.get("first_seen", ""),
                        })
    # Deterministic order, so regenerating the seed from the same export gives the same file.
    rows.sort(key=lambda r: (r["address"].lower(), r["wallet_id"], r["currency"], r["holder_id"]))
    return wallets, rows


def write_csv(rows: list[dict], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def summarise(wallets: int, rows: list[dict]) -> None:
    by_address = {}
    for r in rows:
        by_address.setdefault(r["address"].lower(), set()).add(r["currency"])
    only_other_labels = sum(1 for labels in by_address.values() if "ETH" not in labels)
    mixed_case = len({r["address"] for r in rows if r["address"] != r["address"].lower()})

    print(f"CryptoWallet entities read:              {wallets:,}")
    print(f"Ethereum-format rows written:            {len(rows):,}")
    print(f"Distinct addresses (case-insensitive):   {len(by_address):,}")
    print(f"Addresses on more than one row:          {sum(1 for r in Counter(r['address'].lower() for r in rows).values() if r > 1):,}")
    print(f"Addresses never labelled ETH:            {only_other_labels:,}   <- lost by a currency == 'ETH' filter")
    print(f"Addresses not all-lowercase (checksum):  {mixed_case:,}   <- missed by a case-sensitive join")
    print("Rows by currency label:")
    for currency, n in Counter(r["currency"] for r in rows).most_common():
        print(f"  {currency or '(none)':<6} {n:,}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", type=Path, default=Path("data/entities.ftm.json"))
    parser.add_argument("--output", type=Path, default=Path("seeds/ofac_wallets.csv"))
    args = parser.parse_args()

    if not args.input.exists():
        sys.exit(
            f"Input not found: {args.input}\n"
            "Download entities.ftm.json from https://www.opensanctions.org/datasets/us_ofac_sdn/ "
            "into the data/ folder, or pass --input."
        )
    wallets, rows = extract(args.input)
    if not rows:
        sys.exit("No Ethereum-format addresses found: check the input is the FollowTheMoney export.")
    write_csv(rows, args.output)
    print(f"Wrote {args.output}\n")
    summarise(wallets, rows)


if __name__ == "__main__":
    main()
