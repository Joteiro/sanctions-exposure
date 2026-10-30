-- Step 2 · Column pruning
-- One day (2024-01-01), already partition-filtered. Only the column list changes.
-- Dry run, this version (4 columns):  165.6 MiB
-- Same filter, SELECT *:              2.90 GiB
-- Same filter, SELECT input alone:    2.46 GiB  -> one column of 25 is 84.8% of the cost
SELECT from_address, to_address, value, block_timestamp
FROM `bigquery-public-data.crypto_ethereum.transactions`
WHERE block_timestamp >= TIMESTAMP('2024-01-01')
  AND block_timestamp <  TIMESTAMP('2024-01-02')
