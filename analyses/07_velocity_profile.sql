-- Step 3 · Audit: distribution of the velocity feature, 1 January 2024
-- Backs the velocity table in the README. Gap thresholds are cumulative.
-- Dry run: 129.4 MiB
WITH tx AS (
  SELECT from_address, nonce, block_timestamp
  FROM `bigquery-public-data.crypto_ethereum.transactions`
  WHERE block_timestamp >= TIMESTAMP('2024-01-01')
    AND block_timestamp <  TIMESTAMP('2024-01-02')
    AND receipt_status = 1
    AND value > 0
),
g AS (
  SELECT
    from_address,
    TIMESTAMP_DIFF(
      block_timestamp,
      LAG(block_timestamp) OVER (PARTITION BY from_address ORDER BY block_timestamp, nonce),
      SECOND) AS gap
  FROM tx
)
SELECT
  COUNT(*)                                                AS transfers,
  COUNT(DISTINCT from_address)                            AS senders,
  COUNT(DISTINCT IF(gap IS NOT NULL, from_address, NULL)) AS repeat_senders,
  COUNTIF(gap IS NOT NULL)                                AS follow_ups,
  COUNTIF(gap = 0)                                        AS gap_same_block,
  COUNTIF(gap <= 12)                                      AS gap_le_12s,
  COUNTIF(gap <= 60)                                      AS gap_le_60s,
  COUNTIF(gap <= 3600)                                    AS gap_le_1h,
  APPROX_QUANTILES(gap, 100)[OFFSET(25)]                  AS p25_gap_s,
  APPROX_QUANTILES(gap, 100)[OFFSET(50)]                  AS median_gap_s
FROM g
