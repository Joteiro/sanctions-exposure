# Sanctions Exposure on Public Blockchain Data

Tracing exposure to sanctioned entities through real Ethereum transaction flows, modelled end to end on BigQuery with dbt.

**Status:** work in progress — steps 1–3 of 6 complete.

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

The query behind each figure is in [`analyses/`](analyses/), one per file, with its dry-run size in the header.

> The dry-run figure is an upper bound: on a clustered table the bytes actually billed can come in lower.

## First results

### Daily activity

Ethereum mainnet, 1–7 January 2024, all transactions (including zero-value and failed ones):

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

Top 10 receiving addresses over the same week, successful native transfers with non-zero value, **ordered by total ETH received**. The rightmost column is derived, not source data ([`03_top_receivers.sql`](analyses/03_top_receivers.sql)):

| # | Transactions | Total ETH | ETH per transaction |
|---|---|---|---|
| 1 | 30,675 | 621,644 | 20.27 |
| 2 | 43,653 | 355,558 | 8.15 |
| 3 | 46 | 246,888 | **5,367.14** |
| 4 | 14 | 130,382 | **9,312.97** |
| 5 | 1,136 | 129,528 | 114.02 |
| 6 | 223,217 | 117,468 | **0.53** |
| 7 | 13 | 94,447 | 7,265.12 |
| 8 | 13 | 93,945 | 7,226.57 |
| 9 | 3,907 | 91,694 | 23.47 |
| 10 | 12 | 88,225 | 7,352.11 |

Addresses are deliberately not listed or labelled — see *What this does not do*.

> **Correction.** An earlier version of this table counted failed transactions (`receipt_status = 0`) as value received. A failed transaction moves no ETH. In aggregate the difference is small — 42,816 failed transfers carrying 33,031 ETH over the week, 0.39% of the total — but not per address: rank 6 included 15,861 failed transactions (6,361 ETH), and the previous rank 10 fell to 11. The conclusion below is unchanged; the figures are now right.

Compare rank 3 and rank 6. They received the same order of magnitude of value — 247K and 117K ETH — and sit three places apart in a ranking by value. But rank 3 did it in **46** transactions and rank 6 in **223,217**: an average transfer size roughly **10,000× apart**. Ranks 4, 7, 8 and 10 are the same shape as rank 3 — a dozen or so enormous transfers — while rank 6 is high-frequency, low-value flow.

These are not variations of one behaviour. They are different behaviours that happen to produce similar weekly totals.

The consequence for detection logic is direct: a rule thresholding on **value** treats ranks 3 and 6 as peers, and a rule thresholding on **transaction count** treats them as opposites. Neither describes what is actually happening. And the column that does separate them — average transfer size — **is not in the source data**. It has to be derived.

That is the argument for the next step: per-address behavioural features rather than raw aggregates.

## Behavioural features

The previous section ended on a column the source does not have. This step derives three per-address features with window functions — calculations over a set of related rows that, unlike `GROUP BY`, keep every row.

| Feature | Built with | Measures | Query |
|---|---|---|---|
| Velocity | `LAG` | Seconds since the same address's previous transfer | [`04_velocity.sql`](analyses/04_velocity.sql) |
| Running total | `SUM … OVER (ROWS …)` | ETH sent so far, at every transfer — when an address crosses a threshold | [`05_running_total.sql`](analyses/05_running_total.sql) |
| Counterparty concentration | `ROW_NUMBER` + `SUM … OVER` | Share of an address's outflow that went to its single largest counterparty | [`06_counterparty_concentration.sql`](analyses/06_counterparty_concentration.sql) |

*Transfer* here means a successful native transfer with non-zero value: `receipt_status = 1 AND value > 0`.

Window functions do not change the bill. BigQuery charges for bytes read, not for computation: velocity and running total do different work over the same columns and scan the same **129.4 MiB**. Cost is still governed by the two levers above.

### Same-block ties make a naive running total non-deterministic

`block_timestamp` belongs to the block, not to the transaction. Every transaction in a block shares it, so when one address sends several transfers in the same block, ordering by timestamp produces ties.

On 1 January 2024, **58,067 of 549,904 transfers (10.6%)** tie on timestamp with another transfer from the same sender. They are concentrated in **1,077 addresses**; the largest single tie is **519 transfers from one address in one block**.

The usual warning is about the default frame: with `ORDER BY` inside `OVER` and no frame, BigQuery uses `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, which treats tied rows as peers and gives all of them the same running total. The usual fix is `ROWS`. Measured against a deterministic reference, the fix does not fix it ([`08_tie_audit.sql`](analyses/08_tie_audit.sql)):

| Window | Transfers whose running total differs from the reference |
|---|---|
| `ORDER BY block_timestamp` · `RANGE` (the default) | 34,035 |
| `ORDER BY block_timestamp` · `ROWS` | 35,241 |
| `ORDER BY block_timestamp, nonce` · `ROWS` | *reference* |

`ROWS` processes tied rows one at a time, but in an order the engine is free to choose, so the second figure is not guaranteed to be the same on the next run. `RANGE` is wrong the same way every time; `ROWS` without a tie-breaker can be wrong differently each time.

The tie-breaker is already in the data. `nonce` is a per-sender counter that increases by exactly one with every transaction, so `(block_timestamp, nonce)` is a strict order:

```sql
SUM(eth) OVER (
  PARTITION BY from_address
  ORDER BY block_timestamp, nonce   -- nonce breaks same-block ties
  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS cum_eth_sent
```

It costs one integer column — about 10 MiB per day of data. The same reasoning puts `to_address` behind `eth DESC` in the concentration query's `ROW_NUMBER`: two counterparties with equal totals would otherwise make "the top counterparty" a coin toss.

Velocity is the exception. The gap between tied rows is zero whichever comes first, so its distribution is unaffected; only which row carries which gap changes. The tie-breaker is there anyway, so row-level output is reproducible.

### Velocity: the block is the floor

On 1 January 2024, **45,215 of 304,064 sending addresses (14.9%)** made more than one transfer — and those addresses account for **52.9%** of all transfers. Gaps between an address's consecutive transfers, over 245,840 follow-ups ([`07_velocity_profile.sql`](analyses/07_velocity_profile.sql)):

| Gap to the previous transfer | Share of follow-ups (cumulative) |
|---|---|
| 0 s — same block | 15.0% |
| ≤ 12 s — about one block | 23.9% |
| ≤ 60 s | 42.4% |
| ≤ 1 h | 85.2% |

A quarter of follow-ups arrive within 24 seconds; half within 120 (approximate quantiles).

Two consequences. One follow-up in seven lands in the same block as the one before it, where time carries no information: the resolution of any timestamp-based velocity measure is the block, about 12 seconds, and a rule written in seconds below that measures nothing. And among the addresses that produce most of the volume, a fast follow-up is ordinary. Velocity means something relative to an address's own history or a peer baseline, not as a fixed threshold.

### Concentration: near 1 is the norm, not the signal

1–7 January 2024, the **4,295** addresses that sent more than 100 ETH ([`09_concentration_profile.sql`](analyses/09_concentration_profile.sql)):

| Share of outflow to the top counterparty | Addresses | Share |
|---|---|---|
| Exactly one counterparty | 2,371 | 55.2% |
| ≥ 0.99 | 2,643 | 61.5% |
| ≥ 0.5 | 3,703 | 86.2% |
| < 0.1 | 76 | 1.8% |

Median 1.0; lower quartile 0.68.

The intuitive reading of high concentration is an exclusive relationship, and so a notable one. The distribution rules that out as a standalone rule: among large senders, sending everything to one counterparty is what most addresses do, and a flag at concentration ≥ 0.99 would fire on 61.5% of them. It is the shape a forwarding address produces — receive, pass everything on to one destination — though nothing here confirms that is what they are.

The informative end is the other one: 76 addresses spread more than 100 ETH so evenly that no counterparty received a tenth of it. And concentration earns its place in combination. An address at 1.0 that moves a dozen enormous transfers is a different profile from one at 1.0 sending half an ether a minute — which is exactly the rank 3 / rank 6 contrast above, now expressible as features.

The 100 ETH cut-off is a choice, not a finding: it keeps the population to addresses moving material value. The shape should be re-tested at other cut-offs before anything is built on it.

## Repository layout

```
analyses/   every query behind a figure in this README, one statement per file
```

Each file states its dry-run size in the header. One statement per file is deliberate: the BigQuery console's estimate for a multi-statement script is the sum of all its statements, which makes per-query figures easy to misread. dbt models join in step 4.

## Roadmap

1. ✅ Environment, cost controls, first measured query
2. ✅ Query optimisation: column pruning, measured before and after
3. ✅ Window functions: velocity, running totals, counterparty concentration — and the tie problem
4. ⬜ dbt staging models with schema tests
5. ⬜ Marts: 1-hop and 2-hop exposure, sanctions snapshot, lineage graph
6. ⬜ Evidence-grounded summarisation layer, and the write-up

## What this does not do

Worth stating plainly, because the gap between what a model measures and what people assume it measures is where analysis goes wrong:

- **It does not establish identity.** An address is not a person. No attribution or address-clustering is attempted, and no address is labelled in this repository — including the high-volume ones above, several of which are publicly known. Labelling them would contradict the point.
- **It does not prove wrongdoing.** Proximity to a sanctioned address is an exposure signal, not a finding. Hop distance measures graph distance, nothing more.
- **Features are computed inside fixed windows** — one day for velocity and running totals, one week for concentration. Activity just before a window opens is invisible, so an address's first transfer of the day has no predecessor even if it also transacted a minute before midnight.
- **It does not cover all value transfer.** Internal transactions, token transfers and bridges are out of scope for now, so "total ETH received" means native transfers only.

## Stack

BigQuery (sandbox) · dbt · SQL · Looker Studio

---

Built by Juan Taraciuk ([LinkedIn](https://www.linkedin.com/in/juantaraciuk/) | [Github](https://github.com/Joteiro))
