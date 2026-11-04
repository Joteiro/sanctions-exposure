-- Returns offending rows; the test passes when there are none.
-- Guards the join key: if the seed or the extraction script changes and lets through an
-- address that is not lowercase 0x + 40 hex characters, this fails instead of the join
-- silently matching nothing.
select wallet_id, address
from {{ ref('stg_opensanctions__wallets') }}
where not regexp_contains(address, r'^0x[0-9a-f]{40}$')
