-- Average events per session for Tech Creator hosts
SELECT
    host,
    AVG(event_count) as avg_events_per_session,
    COUNT(*) as total_sessions
FROM web_sessions
WHERE host LIKE '%techcreator.io'
GROUP BY host
ORDER BY avg_events_per_session DESC;

-- Compare specific hosts
SELECT
    host,
    AVG(event_count) as avg_events_per_session,
    COUNT(*) as total_sessions,
    AVG(EXTRACT(EPOCH FROM (session_end - session_start))) as avg_session_duration_seconds
FROM web_sessions
WHERE host IN (
    'zachwilson.techcreator.io',
    'zachwilson.tech',
    'lulu.techcreator.io'
)
GROUP BY host
ORDER BY avg_events_per_session DESC;