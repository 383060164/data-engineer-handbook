-- State Change Tracking Query for Players
WITH player_states AS (
    SELECT
        p1.player_id,
        p1.season as current_season,
        p1.is_active as current_active,
        LAG(p1.is_active) OVER (PARTITION BY p1.player_id ORDER BY p1.season) as previous_active
    FROM players_scd p1
),
player_transitions AS (
    SELECT
        player_id,
        current_season,
        CASE
            -- First season in the data
            WHEN previous_active IS NULL AND current_active = TRUE THEN 'New'
            -- Retired
            WHEN previous_active = TRUE AND current_active = FALSE THEN 'Retired'
            -- Continued playing
            WHEN previous_active = TRUE AND current_active = TRUE THEN 'Continued Playing'
            -- Returned from retirement
            WHEN previous_active = FALSE AND current_active = TRUE THEN 'Returned from Retirement'
            -- Stayed retired
            WHEN previous_active = FALSE AND current_active = FALSE THEN 'Stayed Retired'
        END as state_change
    FROM player_states
)
SELECT
    p.player_name,
    pt.current_season,
    pt.state_change
FROM player_transitions pt
JOIN players p ON p.player_id = pt.player_id
ORDER BY p.player_name, pt.current_season;

-- Efficient Aggregations using GROUPING SETS
WITH game_aggregates AS (
    SELECT
        gd.player_id,
        p.player_name,
        gd.team_id,
        t.team_name,
        gd.season,
        SUM(gd.points) as total_points,
        COUNT(DISTINCT CASE WHEN gd.win = TRUE THEN gd.game_id END) as wins,
        COUNT(DISTINCT gd.game_id) as games_played
    FROM game_details gd
    JOIN players p ON p.player_id = gd.player_id
    JOIN teams t ON t.team_id = gd.team_id
    GROUP BY GROUPING SETS (
        (gd.player_id, p.player_name, gd.team_id, t.team_name),  -- Player and Team
        (gd.player_id, p.player_name, gd.season),                -- Player and Season
        (gd.team_id, t.team_name)                                -- Team only
    )
)
SELECT
    COALESCE(player_name, 'All Players') as player,
    COALESCE(team_name, 'All Teams') as team,
    COALESCE(season::text, 'All Seasons') as season,
    total_points,
    wins,
    games_played,
    ROUND(CAST(wins AS DECIMAL) / NULLIF(games_played, 0) * 100, 2) as win_percentage
FROM game_aggregates
ORDER BY total_points DESC;

-- Most Points by Player for a Single Team
SELECT
    p.player_name,
    t.team_name,
    SUM(gd.points) as total_points,
    COUNT(DISTINCT gd.game_id) as games_played,
    ROUND(CAST(SUM(gd.points) AS DECIMAL) / COUNT(DISTINCT gd.game_id), 2) as points_per_game
FROM game_details gd
JOIN players p ON p.player_id = gd.player_id
JOIN teams t ON t.team_id = gd.team_id
GROUP BY p.player_id, p.player_name, t.team_id, t.team_name
ORDER BY total_points DESC
LIMIT 10;

-- Most Points in a Single Season
SELECT
    p.player_name,
    gd.season,
    SUM(gd.points) as total_points,
    COUNT(DISTINCT gd.game_id) as games_played,
    ROUND(CAST(SUM(gd.points) AS DECIMAL) / COUNT(DISTINCT gd.game_id), 2) as points_per_game
FROM game_details gd
JOIN players p ON p.player_id = gd.player_id
GROUP BY p.player_id, p.player_name, gd.season
ORDER BY total_points DESC
LIMIT 10;

-- Team with Most Total Wins
SELECT
    t.team_name,
    COUNT(DISTINCT CASE WHEN gd.win = TRUE THEN gd.game_id END) as total_wins,
    COUNT(DISTINCT gd.game_id) as total_games,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN gd.win = TRUE THEN gd.game_id END) AS DECIMAL) /
          COUNT(DISTINCT gd.game_id) * 100, 2) as win_percentage
FROM game_details gd
JOIN teams t ON t.team_id = gd.team_id
GROUP BY t.team_id, t.team_name
ORDER BY total_wins DESC;

-- 90-game Team Winning Stretches
WITH team_games AS (
    SELECT
        team_id,
        game_date,
        CASE WHEN win = TRUE THEN 1 ELSE 0 END as won
    FROM game_details
    ORDER BY team_id, game_date
),
rolling_wins AS (
    SELECT
        team_id,
        game_date,
        SUM(won) OVER (
            PARTITION BY team_id
            ORDER BY game_date
            ROWS BETWEEN 89 PRECEDING AND CURRENT ROW
        ) as wins_in_90
    FROM team_games
)
SELECT
    t.team_name,
    rw.wins_in_90 as max_wins,
    rw.game_date as end_date
FROM rolling_wins rw
JOIN teams t ON t.team_id = rw.team_id
WHERE rw.wins_in_90 = (SELECT MAX(wins_in_90) FROM rolling_wins)
ORDER BY rw.wins_in_90 DESC;

-- LeBron's 10+ Point Scoring Streak (Improved version using ROW_NUMBER)
WITH lebron_games AS (
    SELECT
        game_date,
        points,
        CASE WHEN points > 10 THEN 0 ELSE 1 END as streak_break,
        SUM(CASE WHEN points <= 10 THEN 1 ELSE 0 END) OVER (ORDER BY game_date) as streak_group
    FROM game_details gd
    JOIN players p ON p.player_id = gd.player_id
    WHERE p.player_name = 'LeBron James'
    ORDER BY game_date
)
SELECT
    MIN(game_date) as streak_start,
    MAX(game_date) as streak_end,
    COUNT(*) as streak_length,
    ROUND(AVG(points), 2) as avg_points_during_streak
FROM lebron_games
WHERE streak_break = 0
GROUP BY streak_group
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC
LIMIT 1;