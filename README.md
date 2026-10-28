# Sanctions Exposure on Public Blockchain Data

Tracing exposure to sanctioned entities through real Ethereum transaction flows, modelled end to end on BigQuery with dbt.

**Status:** work in progress — steps 1–2 of 6 complete.

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

BigQuery bills on **bytes read**, and only two levers change that number: read fewer rows, and read fewer columns. Both were measured rather than assumed.

### Lever 1 — partition pruning (fewer rows)

`crypto_ethereum.transactions` is exposed as a view over data partitioned on `block_timestamp`. Filtering on that column lets BigQuery discard entire partitions without reading them.

Same query — daily transaction counts and distinct senders across one week:

| Version | Bytes scanned |
|---|---|
| With `WHERE block_timestamp BETWEEN ...` | **381.62 MiB** |
| Without the filter | **184.82 GiB** |

**A 496× difference**, or 99.8% of the scan avoided. The unfiltered version would have consumed **18% of the entire monthly quota in a single run** — and would have been rejected by both guards above.

`LIMIT` does not help. BigQuery reads the columns and partitions you asked for and *then* trims the output; by that point the scan has already happened and been counted.

### Lever 2 — column pruning (narrower rows)

BigQuery is columnar: it reads only the columns named in the query. Measured over a **single day** (2024-01-01), already partition-filtered:

| Query | Bytes scanned | Share of `SELECT *` |
|---|---|---|
| `SELECT *` | 2.90 GiB | 100% |
| `SELECT from_address, to_address, value, block_timestamp` | 165.6 MiB | 5.6% |
| `SELECT input` *(one column)* | 2.46 GiB | **84.8%** |

The third row is the finding. **One column out of twenty-five accounts for ~85% of the table's read cost.** `input` holds the transaction payload — the call data sent to a contract — and this project never reads it: the questions here are about addresses, amounts and timestamps.

So on this table `SELECT *` is, in practice, "fetch the `input` column, plus rounding error". Dropping it is a **17.9×** reduction on its own, before any partition filter is applied.

### Combined

Partition filter and column selection compose. The working query shape for this project — one week, four columns — scans **~620 MiB**, against the ~184 GiB a naive full-table equivalent would have cost.

Every figure above was obtained with a **dry run**, which validates the query and reports the bytes it *would* scan without executing it or consuming quota. Dry runs also catch syntax and type errors, which makes them a free pre-flight check — and a natural thing to wire into CI so a broken query never reaches production.

> The dry-run figure is an upper bound: on a clustered table the bytes actually billed can come in lower.

## First results

### Daily activity

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

### Value received, and why value is not enough

Top 10 receiving addresses over the same week, native transfers with non-zero value, **ordered by total ETH received**. The rightmost column is derived, not source data:

| # | Transactions | Total ETH | ETH per transaction |
|---|---|---|---|
| 1 | 30,675 | 621,644 | 20.27 |
| 2 | 43,653 | 355,558 | 8.15 |
| 3 | 46 | 246,888 | **5,367.14** |
| 4 | 14 | 130,382 | **9,312.97** |
| 5 | 1,136 | 129,528 | 114.02 |
| 6 | 239,078 | 123,829 | **0.52** |
| 7 | 13 | 94,447 | 7,265.12 |
| 8 | 13 | 93,945 | 7,226.57 |
| 9 | 3,907 | 91,694 | 23.47 |
| 10 | 16,924 | 88,871 | 5.25 |

Addresses are deliberately not listed or labelled — see *What this does not do*.

Compare rank 3 and rank 6. They received the same order of magnitude of value — 247K and 124K ETH — and sit four places apart in a ranking by value. But rank 3 did it in **46** transactions and rank 6 in **239,078**: an average transfer size roughly **10,000× apart**. Ranks 4, 7 and 8 are the same shape as rank 3 — a dozen or so enormous transfers — while ranks 6 and 10 are high-frequency, low-value flow.

These are not variations of one behaviour. They are different behaviours that happen to produce similar weekly totals.

The consequence for detection logic is direct: a rule thresholding on **value** treats ranks 3 and 6 as peers, and a rule thresholding on **transaction count** treats them as opposites. Neither describes what is actually happening. And the column that does separate them — average transfer size — **is not in the source data**. It has to be derived.

That is the argument for the next step: per-address behavioural features rather than raw aggregates.

## Roadmap

1. ✅ Environment, cost controls, first measured query
2. ✅ Query optimisation: column pruning, measured before and after
3. ⬜ Window functions: running balances, time between transactions, counterparty ranking
4. ⬜ dbt staging models with schema tests
5. ⬜ Marts: 1-hop and 2-hop exposure, sanctions snapshot, lineage graph
6. ⬜ Evidence-grounded summarisation layer, and the write-up

## What this does not do

Worth stating plainly, because the gap between what a model measures and what people assume it measures is where analysis goes wrong:

- **It does not establish identity.** An address is not a person. No attribution or address-clustering is attempted, and no address is labelled in this repository — including the high-volume ones above, several of which are publicly known. Labelling them would contradict the point.
- **It does not prove wrongdoing.** Proximity to a sanctioned address is an exposure signal, not a finding. Hop distance measures graph distance, nothing more.
- **It does not cover all value transfer.** Internal transactions, token transfers and bridges are out of scope for now, so "total ETH received" means native transfers only.

## Stack

BigQuery (sandbox) · dbt · SQL · Looker Studio

---

Built by Juan Taraciuk ([LinkedIn](https://www.linkedin.com/in/juantaraciuk/) | [Github](https://github.com/Joteiro))
