-- One row per sanctioned Ethereum address. Staging has one row per wallet entity;
-- the join to transfers needs one row per address, or each transfer is counted
-- once per wallet that shares its address.
select
    address,
    min(first_seen_at)                             as first_listed_at,
    date(min(first_seen_at)) > date('{{ var("opensanctions_tracking_start") }}')
                                                   as listing_date_known,
    count(*)                                       as wallet_entities,
    array_agg(distinct currency order by currency) as currency_labels,
    count(distinct holder_id)                      as holders
from {{ ref('stg_opensanctions__wallets') }}
group by address