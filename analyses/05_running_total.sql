-- Step 3 · Feature: running total sent (SUM OVER with an explicit frame)
-- Cumulative ETH sent by each address up to and including each transfer, 1 January 2024.
-- Two windows: one ordered (running total), one unordered (whole-partition count).
-- The frame is ROWS, and the order has a tie-breaker: without nonce, ROWS is
-- non-deterministic on same-block transactions (see 08_tie_audit.sql).
-- Dry run: 129.4 MiB (identical to 04: window functions do not add bytes read)
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
  SUM(eth) OVER (
    PARTITION BY from_address
    ORDER BY block_timestamp, nonce
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )                                        AS cum_eth_sent,
  COUNT(*) OVER (PARTITION BY from_address) AS transfers_that_day
FROM tx
ORDER BY from_address, block_timestamp, nonce
LIMIT 100
