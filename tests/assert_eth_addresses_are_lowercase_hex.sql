-- Returns offending rows; the test passes when there are none.
select from_address, to_address
from {{ ref('stg_ethereum__transactions') }}
where not regexp_contains(from_address, r'^0x[0-9a-f]{40}$')
   or (to_address is not null and not regexp_contains(to_address, r'^0x[0-9a-f]{40}$'))