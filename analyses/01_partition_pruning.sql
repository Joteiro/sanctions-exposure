-- Step 1 · Partition pruning
-- Daily transactions and distinct senders, 1–7 January 2024.
-- Dry run with the WHERE clause:    381.62 MiB
-- Dry run without it (do not run):  184.82 GiB  -> 496x more, 18% of the monthly quota
SELECT
  DATE(block_timestamp)        AS day,
  COUNT(*)                     AS tx_count,
  COUNT(DISTINCT from_address) AS senders
FROM `bigquery-public-data.crypto_ethereum.transactions`
WHERE block_timestamp >= TIMESTAMP('2024-01-01')
  AND block_timestamp <  TIMESTAMP('2024-01-08')
GROUP BY day
ORDER BY day
