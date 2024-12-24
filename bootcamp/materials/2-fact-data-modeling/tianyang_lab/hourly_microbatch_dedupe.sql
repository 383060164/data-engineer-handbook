--Hourly microbatch dedupe
--Dedupe each hour with GROUP BY
-- Use SUM and COUNT to aggregate duplicates, use COLLECT_LIST to collect metadata about the duplicates that might be different!
SELECT
product_id, event_type,
MIN(event_timestamp_epoch) as min_event_timestamp_epoch, MAX(event_timestamp_epoch) AS max_event_timestamp_epoch,
MAP_FROM_ARRAYS (
COLLECT_LIST(event_location),
COLLECT_LIST (event_timestamp_epoch)
) AS event_locations
FROM event_source
GROUP BY product id. event tvoe
--Dedupe between hours with FULL OUTER JOIN like branches of a tree
-- - Use left.value + right.value to keep duplicates aggregation correctly counting or CONCAT to build a continuous list
WITH earlier AS (
SELECT * FROM hourly_deduped_source
WHERE {ds_str} AND hour = {earlier_hour) AND product_name = (product_name)
later AS X
SELECT * FROM hourly_deduped_source
WHERE {ds_str} AND hour = {later_hour) AND product_name = (product_name)
SELECT
COALESCE(e-product_id, l.product_id) as product_id, COALESCE (e.event_type, l.event_type) AS event_type,
COALESCE(e.min_event_timestamp_epoch, l.min_event_timestamp_epoch) as min_event_timestamp_epoch, COALESCE(l.max_event_timestamp_epoch, e.max_event_timestamp_epoch) AS max_event_timestamp_epoch,
CONCAT (e.event_locations, l.event_locations) as event_locations
FROM earlier e
FULL OUTER JOIN later l
ON e.product_id = l. product_id
 e. event type = l. event type