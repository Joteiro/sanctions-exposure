-- Step 5 · Distinct addresses with at least one transfer in the window (sender or receiver).
-- The denominator for "share of active addresses" in the README.
-- Dry run: about 1.4 GiB (int_transfers is a view over both staging tables).
select count(distinct address) as active_addresses
from (
    select from_address as address from {{ ref('int_transfers') }}
    union all
    select to_address from {{ ref('int_transfers') }}
)
