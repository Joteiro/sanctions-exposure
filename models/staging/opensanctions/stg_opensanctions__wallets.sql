-- Sanctioned wallets from the OpenSanctions US OFAC SDN export, Ethereum-format addresses only.
-- Grain: one row per wallet entity (wallet_id). The same address can appear on several rows,
-- because OFAC lists one wallet per currency label (for example ETH and USDT for one address).
-- Collapsing to one row per address is left to the join that needs it (step 5).
--
-- No WHERE clause on purpose: scripts/extract_wallets.py already keeps only Ethereum-format
-- addresses. Filtering again here would hide a broken seed; the singular test
-- tests/assert_sanctioned_addresses_are_lowercase_hex.sql catches it instead.

with source as (
    select * from {{ ref('ofac_wallets') }}
)

select
    wallet_id,
    lower(trim(address))          as address,        -- Ethereum data is lowercase; OFAC often publishes mixed-case checksum format
    currency,                                         -- label as listed (ETH, USDT, ARB...): kept, never used as a filter
    holder_id,                                        -- OpenSanctions id of the sanctioned person or organisation
    cast(first_seen as timestamp) as first_seen_at   -- when OpenSanctions first saw the entry, NOT the OFAC designation date
from source
