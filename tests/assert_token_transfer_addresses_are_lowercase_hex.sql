-- Returns offending rows; the test passes when there are none.
-- Same guard as for transactions: every address that will be joined on must be
-- lowercase 0x + 40 hex characters, including the token contract.
select block_number, log_index, from_address, to_address, token_address
from {{ ref('stg_ethereum__token_transfers') }}
where not regexp_contains(from_address,  r'^0x[0-9a-f]{40}$')
   or not regexp_contains(to_address,    r'^0x[0-9a-f]{40}$')
   or not regexp_contains(token_address, r'^0x[0-9a-f]{40}$')
