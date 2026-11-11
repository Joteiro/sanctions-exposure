-- Every value-moving transfer in the window, native ETH and tokens, in one shape.
-- Native: only successful transactions that carry value (a failed or zero-value
-- transaction moves no ETH). Tokens: every transfer event (a failed transaction
-- emits none).
select
    concat('eth:', from_address, ':', cast(nonce as string)) as transfer_id,
    'ETH'                 as asset,
    from_address,
    to_address,
    value_eth,
    block_timestamp
from {{ ref('stg_ethereum__transactions') }}
where receipt_status = 1
  and value_wei > 0
  and to_address is not null

union all

select
    concat('token:', cast(block_number as string), ':', cast(log_index as string)),
    token_address,
    from_address,
    to_address,
    cast(null as numeric) as value_eth,   -- token amounts are not converted
    block_timestamp
from {{ ref('stg_ethereum__token_transfers') }}