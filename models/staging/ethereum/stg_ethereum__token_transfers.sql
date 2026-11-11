{{ config(
    partition_by={'field': 'block_timestamp', 'data_type': 'timestamp', 'granularity': 'day'},
    cluster_by=['from_address']
) }}

select
    block_number,
    log_index,                            -- position of the event in its block: (block_number, log_index) is the key
    lower(token_address) as token_address,
    lower(from_address)  as from_address,
    lower(to_address)    as to_address,
    value                as amount_raw,   -- integer in the token's smallest unit, as text: decimals differ per token
    block_timestamp
from {{ source('ethereum', 'token_transfers') }}
where block_timestamp >= timestamp('{{ var("start_date") }}')
  and block_timestamp <  timestamp('{{ var("end_date") }}')