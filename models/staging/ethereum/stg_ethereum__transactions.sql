{{ config(
    partition_by={'field': 'block_timestamp', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['from_address']
) }}

select
    nonce,
    lower(from_address) as from_address,
    lower(to_address)   as to_address,      -- null = contract creation
    value               as value_wei,
    value / 1e18        as value_eth,
    block_timestamp,
    block_number,
    receipt_status                          -- 1 = success, 0 = failed (moved no ETH)
from {{ source('ethereum', 'transactions') }}
where block_timestamp >= timestamp('{{ var("start_date") }}')
  and block_timestamp <  timestamp('{{ var("end_date") }}')