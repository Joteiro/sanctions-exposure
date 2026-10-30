-- Step 3 · Feature: counterparty concentration (ROW_NUMBER + SUM OVER)
-- Share of each address's outflow that went to its single largest counterparty,
-- 1–7 January 2024, addresses that sent more than 100 ETH.
-- to_address breaks ties in ROW_NUMBER so the "top" counterparty is reproducible.
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
    from_address, to_address, eth,
    ROW_NUMBER() OVER (PARTITION BY from_address ORDER BY eth DESC, to_address) AS rn,
    SUM(eth)     OVER (PARTITION BY from_address)                               AS total_eth
  FROM pairs
)
SELECT
  from_address,
  to_address                  AS top_counterparty,
  eth                         AS top_eth,
  total_eth,
  SAFE_DIVIDE(eth, total_eth) AS concentration
FROM ranked
WHERE rn = 1 AND total_eth > 100
ORDER BY total_eth DESC
LIMIT 50
