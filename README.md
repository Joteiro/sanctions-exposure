# Sanctions Exposure on Public Blockchain Data

Tracing exposure to sanctioned entities through real Ethereum transaction flows, modelled end to end on BigQuery with dbt.

**Status:** work in progress — step 1 of 6 complete.

---

## What this is

A data pipeline that joins **real on-chain transaction flows** against **real sanctions data** to answer:

- Which flows touch addresses belonging to sanctioned entities?
- How many hops away from a sanctioned address is a given counterparty?
- How much value moved, and over what period?
- Which addresses became risky *retroactively*, because a designation was published after the activity took place?

That last question is the interesting one. A sanctions designation applies to past activity, so an address that was clean yesterday is not clean today. Modelling it honestly means treating the sanctions list as a slowly changing dimension, not a static lookup.

## Data sources

Both are public and real.

| Source | What it provides |
|---|---|
| [`bigquery-public-data.crypto_ethereum`](https://console.cloud.google.com/marketplace/details/bigquery-public-data/crypto-ethereum-blockchain) | Ethereum mainnet transaction data, maintained by Google |
| [OpenSanctions](https://www.opensanctions.org/) | Sanctioned entities and PEPs, including crypto wallet addresses published by OFAC |

**No synthetic data.** Every figure in this repository comes from one of the two sources above. Synthetic data hides precisely the failure modes that matter — inconsistent identifiers, nulls where you did not expect them, distributions that do not behave. If something is awkward here, it is awkward because the real data is.

> OpenSanctions is open data under its own terms. This repository links to the source and does not redistribute bulk extracts.

## Cost control

This runs on the BigQuery sandbox: **1 TiB of query processing per month**, against a source measured in terabytes. Every query has to earn its scan.

Two guards are set before any query runs:

- **Per query** — `Maximum bytes billed` = 5 GB. A query that would exceed it is rejected *before* execution rather than billed.
- **Per day** — project quota `Query usage per day` lowered from its 200 TiB default to **50 GiB**.

### Measurement: partition pruning

`crypto_ethereum.transactions` is exposed as a view over data partitioned on `block_timestamp`. Filtering on that column lets BigQuery discard entire partitions without reading them.

Same query — daily transaction counts and distinct senders across one week — measured with a dry run:

| Version | Bytes scanned |
|---|---|
| With `WHERE block_timestamp BETWEEN ...` | **381.62 MiB** |
| Without the filter | **184.82 GiB** |

**A 496× difference**, or 99.8% of the scan avoided. The unfiltered version would have consumed **18% of the entire monthly quota in a single run** — and would have been rejected by both guards above.

`LIMIT` does not help. BigQuery reads the columns and partitions you asked for and *then* trims the output; by that point the scan has already happened and been counted.

## First result

Ethereum mainnet, 1–7 January 2024:

| Day | Transactions | Distinct senders |
|---|---|---|
| 2024-01-01 | 1,101,465 | 413,772 |
| 2024-01-02 | 1,128,657 | 381,274 |
| 2024-01-03 | 1,092,220 | 340,732 |
| 2024-01-04 | 1,116,573 | 347,124 |
| 2024-01-05 | 1,069,252 | 341,397 |
| 2024-01-06 | 994,947 | 324,336 |
| 2024-01-07 | 1,049,831 | 397,726 |

Roughly 1.08M transactions per day from about 364K distinct senders.

The lowest count falls on Saturday 6 January. Seven days is not enough to claim a weekly pattern — but it is enough to note that any monitoring baseline should *test* for one before treating a drop as anomalous.

## Roadmap

1. ✅ Environment, cost controls, first measured query
2. ⬜ Query optimisation: column pruning, measured before and after
3. ⬜ Window functions: running balances, time between transactions, counterparty ranking
4. ⬜ dbt staging models with schema tests
5. ⬜ Marts: 1-hop and 2-hop exposure, sanctions snapshot, lineage graph
6. ⬜ Evidence-grounded summarisation layer, and the write-up

## What this does not do

Worth stating plainly, because the gap between what a model measures and what people assume it measures is where analysis goes wrong:

- **It does not establish identity.** An address is not a person. No attribution or address-clustering is attempted here.
- **It does not prove wrongdoing.** Proximity to a sanctioned address is an exposure signal, not a finding. Hop distance is a measure of graph distance, nothing more.
- **It does not cover all value transfer.** Internal transactions, token transfers and bridges are out of scope for now.

## Stack

BigQuery (sandbox) · dbt · SQL · Looker Studio

---

Built by Juan Taraciuk ([LinkedIn](https://www.linkedin.com/in/juantaraciuk/) | [Github](https://github.com/Joteiro))
