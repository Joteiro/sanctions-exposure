-- Step 5 · Addresses by hop distance, and how many two-hop addresses survive the hub filter.
-- Backs the hop and threshold tables in the README. The mart holds the result for the
-- threshold it was last built with, so rebuild it before each run:
--   dbt build --select fct_address_exposure_hops --vars "{hub_degree_threshold: 100}"
-- then read without_hubs on the hop_distance = 2 row.
-- Reads only the mart: about 2 MiB.
select
    hop_distance,
    count(*)                                  as addresses,
    countif(is_hub)                           as hubs,
    countif(not reached_only_through_hubs)    as without_hubs
from {{ ref('fct_address_exposure_hops') }}
group by hop_distance
order by hop_distance
