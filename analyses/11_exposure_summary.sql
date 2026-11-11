-- Step 5 · Direct exposure by listing status at the time of the transfer.
-- Backs the direct-exposure table in the README. The last row (listing_status null) is the total.
-- To run: dbt compile --select 11_exposure_summary, then paste the compiled SQL
-- from target/compiled/ into the BigQuery console.
-- Reads only the mart: a few KiB.
select
    listing_status,
    count(*)                             as exposure_rows,
    count(distinct transfer_id)          as transfers,
    count(distinct sanctioned_address)   as sanctioned_addresses,
    count(distinct counterparty_address) as counterparties,
    min(date(first_listed_at))           as earliest_listing,
    max(date(first_listed_at))           as latest_listing
from {{ ref('fct_sanctioned_exposure') }}
group by rollup(listing_status)
order by listing_status nulls last
