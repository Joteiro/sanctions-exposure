-- Step 4 · Audit: does normalising address case change what the join finds?
-- Of the sanctioned Ethereum addresses, how many appear in the week's transactions
-- (as sender or receiver), joining on the address as published vs lowercased.
-- Ethereum data is lowercase; OpenSanctions publishes many addresses in mixed-case
-- checksum format, so a case-sensitive join misses them without any error.
-- To run: dbt compile --select 10_case_sensitivity, then paste the compiled SQL
-- from target/compiled/ into the BigQuery console.
-- Dry run: 633.6 MiB (reads from_address and to_address of stg_ethereum__transactions)
with sanctioned_as_published as (
    select distinct trim(address) as address
    from {{ ref('ofac_wallets') }}
),
sanctioned_normalised as (
    select distinct address
    from {{ ref('stg_opensanctions__wallets') }}
),
tx_addresses as (
    select from_address as address from {{ ref('stg_ethereum__transactions') }}
    union distinct
    select to_address from {{ ref('stg_ethereum__transactions') }}
    where to_address is not null
)
select
    (select count(*) from sanctioned_normalised)                                     as sanctioned_addresses,
    (select count(*) from sanctioned_as_published join tx_addresses using (address)) as matched_as_published,
    (select count(*) from sanctioned_normalised   join tx_addresses using (address)) as matched_normalised
