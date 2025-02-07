-- Calculate average events per session for each host
WITH host_stats AS (
    SELECT
        host,
        COUNT(*) as total_sessions,
        AVG(event_count) as avg_events_per_session,
        STDDEV(event_count) as stddev_events,
        MIN(event_count) as min_events,
        MAX(event_count) as max_events
    FROM web_sessions
    GROUP BY host
)
SELECT
    host,
    total_sessions,
    ROUND(avg_events_per_session, 2) as avg_events,
    ROUND(stddev_events, 2) as stddev_events,
    min_events,
    max_events
FROM host_stats
WHERE host IN (
    'zachwilson.techcreator.io',
    'zachwilson.tech',
    'lulu.techcreator.io'
)
ORDER BY avg_events_per_session DESC;

-- Compare session patterns across different times of day
SELECT
    host,
    EXTRACT(HOUR FROM session_start) as hour_of_day,
    COUNT(*) as session_count,
    ROUND(AVG(event_count), 2) as avg_events
FROM web_sessions
WHERE host IN (
    'zachwilson.techcreator.io',
    'zachwilson.tech',
    'lulu.techcreator.io'
)
GROUP BY host, EXTRACT(HOUR FROM session_start)
ORDER BY host, hour_of_day;