-- Step 2 · Top receivers by value, 1–7 January 2024
-- Successful native transfers only (receipt_status = 1): a failed transaction moves no ETH.
-- eth_per_tx is derived; it is not in the source.
-- Dry run: 674.9 MiB
SELECT
  to_address,
  COUNT(*)                                 AS tx_count,
  SUM(value) / 1e18                        AS total_eth,
  SAFE_DIVIDE(SUM(value) / 1e18, COUNT(*)) AS eth_per_tx
FROM `bigquery-public-data.crypto_ethereum.transactions`
WHERE block_timestamp >= TIMESTAMP('2024-01-01')
  AND block_timestamp <  TIMESTAMP('2024-01-08')
  AND to_address IS NOT NULL
  AND receipt_status = 1
  AND value > 0
GROUP BY to_address
ORDER BY total_eth DESC
LIMIT 10
