-- Direct (one-hop) exposure: every transfer with a sanctioned address on either side.
-- Grain: one row per (transfer, sanctioned party). A transfer between two sanctioned
-- addresses appears twice, once from each side.
with sanctioned as (
    select address, first_listed_at, listing_date_known
    from {{ ref('int_sanctioned_addresses') }}
),

transfers as (
    select transfer_id, asset, from_address, to_address, value_eth, block_timestamp
    from {{ ref('int_transfers') }}
),

legs as (
    select t.transfer_id, t.asset, t.block_timestamp, t.value_eth,
           s.address as sanctioned_address, 'sent' as direction, t.to_address as counterparty_address,
           s.first_listed_at, s.listing_date_known
    from transfers t join sanctioned s on t.from_address = s.address
    union all
    select t.transfer_id, t.asset, t.block_timestamp, t.value_eth,
           s.address, 'received', t.from_address,
           s.first_listed_at, s.listing_date_known
    from transfers t join sanctioned s on t.to_address = s.address
)

select
    transfer_id,
    asset,
    block_timestamp,
    sanctioned_address,
    direction,
    counterparty_address,
    value_eth,
    first_listed_at,
    case
        when block_timestamp >= first_listed_at then 'already_listed'
        when listing_date_known                 then 'listed_later'
        else 'unknown'
    end as listing_status
from legs