-- Step 3 · Feature: velocity (LAG)
-- Seconds since the same sender's previous value transfer, 1 January 2024.
-- "Value transfer" throughout: receipt_status = 1 AND value > 0.
-- nonce breaks ties between transactions in the same block (see 08_tie_audit.sql).
-- Dry run: 129.4 MiB
WITH tx AS (
  SELECT from_address, nonce, block_timestamp, value / 1e18 AS eth
  FROM `bigquery-public-data.crypto_ethereum.transactions`
  WHERE block_timestamp >= TIMESTAMP('2024-01-01')
    AND block_timestamp <  TIMESTAMP('2024-01-02')
    AND receipt_status = 1
    AND value > 0
)
SELECT
  from_address, nonce, block_timestamp, eth,
  LAG(block_timestamp) OVER w                                          AS prev_ts,
  TIMESTAMP_DIFF(block_timestamp, LAG(block_timestamp) OVER w, SECOND) AS secs_since_prev
FROM tx
WINDOW w AS (PARTITION BY from_address ORDER BY block_timestamp, nonce)
ORDER BY from_address, block_timestamp, nonce
LIMIT 100
