-- Every address within two hops of a sanctioned address, by shortest graph distance.
-- Hops ignore direction and time: this measures who transacted with whom, not where
-- funds flowed. A hub is an address with more counterparties than
-- var('hub_degree_threshold') in the window: exchanges, routers, popular contracts.
with edges as (
    select distinct a, b
    from (
        select from_address as a, to_address as b from {{ ref('int_transfers') }}
        union all
        select to_address, from_address from {{ ref('int_transfers') }}
    )
    where a != b
),

degree as (
    select a as address, count(*) as counterparties
    from edges
    group by a
),

hop0 as (
    select address from {{ ref('int_sanctioned_addresses') }}
),

hop1 as (
    select distinct e.b as address
    from edges e
    join hop0 on e.a = hop0.address
    where e.b not in (select address from hop0)
),

hop2 as (
    select
        e.b as address,
        logical_and(d.counterparties > {{ var('hub_degree_threshold') }}) as reached_only_through_hubs
    from edges e
    join hop1 on e.a = hop1.address
    join degree d on d.address = hop1.address
    where e.b not in (select address from hop0)
      and e.b not in (select address from hop1)
    group by e.b
),

hops as (
    select address, 0 as hop_distance, cast(null as bool) as reached_only_through_hubs from hop0
    union all
    select address, 1, cast(null as bool) from hop1
    union all
    select address, 2, reached_only_through_hubs from hop2
)

select
    h.address,
    h.hop_distance,
    d.counterparties,                                                       -- null: no transfers in the window
    coalesce(d.counterparties > {{ var('hub_degree_threshold') }}, false) as is_hub,
    h.reached_only_through_hubs                                            -- hop 2 only
from hops h
left join degree d using (address)