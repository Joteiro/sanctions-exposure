-- Step 3 · Audit: distribution of the concentration feature, 1–7 January 2024
-- Backs the concentration table in the README. Same population as 06.
-- Dry run: 997.8 MiB
WITH pairs AS (
  SELECT from_address, to_address, SUM(value) / 1e18 AS eth
  FROM `bigquery-public-data.crypto_ethereum.transactions`
  WHERE block_timestamp >= TIMESTAMP('2024-01-01')
    AND block_timestamp <  TIMESTAMP('2024-01-08')
    AND to_address IS NOT NULL
    AND receipt_status = 1
    AND value > 0
  GROUP BY from_address, to_address
),
ranked AS (
  SELECT
    eth,
    ROW_NUMBER() OVER (PARTITION BY from_address ORDER BY eth DESC, to_address) AS rn,
    SUM(eth)     OVER (PARTITION BY from_address)                               AS total_eth,
    COUNT(*)     OVER (PARTITION BY from_address)                               AS counterparties
  FROM pairs
),
top AS (
  SELECT SAFE_DIVIDE(eth, total_eth) AS c, counterparties
  FROM ranked
  WHERE rn = 1 AND total_eth > 100
)
SELECT
  COUNT(*)                    AS senders_over_100_eth,
  COUNTIF(counterparties = 1) AS single_counterparty,
  COUNTIF(c >= 0.99)          AS c_ge_0_99,
  COUNTIF(c >= 0.5)           AS c_ge_0_5,
  COUNTIF(c < 0.1)            AS c_lt_0_1,
  APPROX_QUANTILES(c, 4)      AS quartiles
FROM top
