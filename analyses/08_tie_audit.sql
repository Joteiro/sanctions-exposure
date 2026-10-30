-- Step 3 · Audit: what same-block ties do to a running total, 1 January 2024
-- block_timestamp is per block, not per transaction, so one sender's transactions
-- in the same block tie. Compares three window definitions against a deterministic
-- reference ordered by (block_timestamp, nonce).
-- rows_ne_reference is itself non-deterministic: it can change between runs.
-- Dry run: 129.4 MiB
WITH tx AS (
  SELECT from_address, nonce, block_timestamp, value / 1e18 AS eth
  FROM `bigquery-public-data.crypto_ethereum.transactions`
  WHERE block_timestamp >= TIMESTAMP('2024-01-01')
    AND block_timestamp <  TIMESTAMP('2024-01-02')
    AND receipt_status = 1
    AND value > 0
),
w AS (
  SELECT
    from_address,
    SUM(eth) OVER (PARTITION BY from_address ORDER BY block_timestamp
                   RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_range,
    SUM(eth) OVER (PARTITION BY from_address ORDER BY block_timestamp
                   ROWS  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_rows,
    SUM(eth) OVER (PARTITION BY from_address ORDER BY block_timestamp, nonce
                   ROWS  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_reference,
    COUNT(*) OVER (PARTITION BY from_address, block_timestamp)       AS tie_size
  FROM tx
)
SELECT
  COUNT(*)                                             AS transfers,
  COUNTIF(tie_size > 1)                                AS transfers_in_ties,
  COUNT(DISTINCT IF(tie_size > 1, from_address, NULL)) AS senders_with_ties,
  MAX(tie_size)                                        AS largest_tie,
  COUNTIF(cum_range != cum_reference)                  AS range_ne_reference,
  COUNTIF(cum_rows  != cum_reference)                  AS rows_ne_reference
FROM w
