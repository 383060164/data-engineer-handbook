-- 1. Deduplication query for game_details
-- Explicitly specify columns to ensure precise deduplication
CREATE TABLE game_details_deduped AS
SELECT DISTINCT
    game_id,
    team_id,
    player_id
FROM game_details;

-- 2. DDL for user_devices_cumulated
-- Using JSONB approach for MAP<STRING, ARRAY[DATE]> implementation
CREATE TABLE user_devices_cumulated (
    user_id VARCHAR(255) PRIMARY KEY,
    device_activity_datelist JSONB,  -- Stores browser_type -> date[] mapping
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Cumulative query for device_activity_datelist
-- Aggregates user activity dates by browser type into a JSONB structure
WITH daily_activity AS (
    -- First, gather distinct daily activities per user and browser
    SELECT
        user_id,
        browser_type,
        DATE(event_timestamp) as activity_date
    FROM web_events  -- Specifically using web_events table
    GROUP BY user_id, browser_type, DATE(event_timestamp)
),
grouped_activity AS (
    -- Then, create the browser_type -> dates mapping
    SELECT
        user_id,
        jsonb_object_agg(
            browser_type,
            (
                SELECT jsonb_agg(DISTINCT activity_date ORDER BY activity_date)
                FROM daily_activity d2
                WHERE d2.user_id = d1.user_id
                AND d2.browser_type = d1.browser_type
            )
        ) as device_activity_datelist
    FROM daily_activity d1
    GROUP BY user_id
)
INSERT INTO user_devices_cumulated (user_id, device_activity_datelist)
SELECT * FROM grouped_activity;

-- 4. datelist_int generation query
-- Converts date arrays to arrays of Unix timestamps
WITH browser_activity AS (
    -- Extract browser types and dates from JSONB
    SELECT
        user_id,
        browser_type,
        jsonb_array_elements_text(device_activity_datelist->browser_type)::date as activity_date
    FROM user_devices_cumulated,
    jsonb_object_keys(device_activity_datelist) as browser_type
),
date_integers AS (
    -- Convert dates to Unix timestamps
    SELECT
        user_id,
        browser_type,
        jsonb_build_object(
            browser_type,
            array_agg(EXTRACT(EPOCH FROM activity_date)::INTEGER ORDER BY activity_date)
        ) as datelist_int
    FROM browser_activity
    GROUP BY user_id, browser_type
)
UPDATE user_devices_cumulated
SET
    device_activity_datelist = (
        SELECT jsonb_object_agg(key, value)
        FROM (
            SELECT key, value
            FROM jsonb_each(date_integers.datelist_int)
        ) t
    ),
    updated_at = CURRENT_TIMESTAMP
FROM date_integers
WHERE user_devices_cumulated.user_id = date_integers.user_id;

-- 5. DDL for hosts_cumulated
CREATE TABLE hosts_cumulated (
    host VARCHAR(255) PRIMARY KEY,
    host_activity_datelist DATE[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. Incremental query for host_activity_datelist
WITH new_activity AS (
    -- Gather new daily activity for hosts
    SELECT
        host,
        array_agg(DISTINCT DATE(event_timestamp) ORDER BY DATE(event_timestamp)) as new_dates
    FROM web_events  -- Specifically using web_events table
    WHERE DATE(event_timestamp) = CURRENT_DATE
    GROUP BY host
)
INSERT INTO hosts_cumulated (host, host_activity_datelist)
SELECT
    na.host,
    na.new_dates
FROM new_activity na
ON CONFLICT (host) DO UPDATE
SET
    host_activity_datelist = array(
        SELECT DISTINCT unnest(hosts_cumulated.host_activity_datelist || EXCLUDED.host_activity_datelist)
        ORDER BY 1
    ),
    updated_at = CURRENT_TIMESTAMP;

-- 7. DDL for host_activity_reduced
CREATE TABLE host_activity_reduced (
    month DATE,
    host VARCHAR(255),
    hit_array INTEGER[],
    unique_visitors_array INTEGER[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (month, host)
);

-- 8. Incremental query for host_activity_reduced
WITH daily_stats AS (
    -- Calculate daily statistics
    SELECT
        DATE_TRUNC('month', DATE(event_timestamp)) as month,
        host,
        DATE(event_timestamp) as activity_date,
        COUNT(1) as hits,
        COUNT(DISTINCT user_id) as unique_visitors
    FROM web_events  -- Specifically using web_events table
    WHERE DATE(event_timestamp) = CURRENT_DATE
    GROUP BY
        DATE_TRUNC('month', DATE(event_timestamp)),
        host,
        DATE(event_timestamp)
)
INSERT INTO host_activity_reduced (
    month,
    host,
    hit_array,
    unique_visitors_array
)
SELECT
    month,
    host,
    ARRAY[hits],
    ARRAY[unique_visitors]
FROM daily_stats
ON CONFLICT (month, host) DO UPDATE
SET
    hit_array = array_append(host_activity_reduced.hit_array, EXCLUDED.hit_array[1]),
    unique_visitors_array = array_append(host_activity_reduced.unique_visitors_array, EXCLUDED.unique_visitors_array[1]),
    updated_at = CURRENT_TIMESTAMP;