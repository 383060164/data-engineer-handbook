-- 1. DDL for actors table (simplified without generated columns)
CREATE TYPE film_details AS (
    film VARCHAR(255),
    votes INTEGER,
    rating DECIMAL(3,1),
    filmid UUID,
    year INTEGER
);

CREATE TABLE actors (
    actorid UUID PRIMARY KEY,
    actor_name VARCHAR(255) NOT NULL,
    films film_details[],
    quality_class VARCHAR(10),
    is_active BOOLEAN,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Cumulative table generation query (with quality_class calculation)
WITH yearly_films AS (
    SELECT
        af.actorid,
        af.actor,
        array_agg(
            ROW(
                af.film,
                af.votes,
                af.rating,
                af.filmid,
                af.year
            )::film_details
        ) as films,
        -- Calculate average rating for current year films
        AVG(CASE
            WHEN af.year = EXTRACT(YEAR FROM CURRENT_DATE)
            THEN af.rating
            END
        ) as current_year_avg_rating,
        -- Check if any films exist in current year
        bool_or(af.year = EXTRACT(YEAR FROM CURRENT_DATE)) as has_current_films
    FROM actor_films af
    WHERE af.year <= EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY af.actorid, af.actor
)
INSERT INTO actors (actorid, actor_name, films, quality_class, is_active)
SELECT
    actorid,
    actor,
    films,
    CASE
        WHEN current_year_avg_rating > 8 THEN 'star'
        WHEN current_year_avg_rating > 7 THEN 'good'
        WHEN current_year_avg_rating > 6 THEN 'average'
        ELSE 'bad'
    END as quality_class,
    has_current_films as is_active
FROM yearly_films;

-- 3. DDL for actors_history_scd table (unchanged)
CREATE TABLE actors_history_scd (
    history_id SERIAL PRIMARY KEY,
    actorid UUID NOT NULL,
    actor_name VARCHAR(255) NOT NULL,
    quality_class VARCHAR(10) NOT NULL,
    is_active BOOLEAN NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    is_current BOOLEAN NOT NULL,
    CONSTRAINT valid_dates CHECK (end_date IS NULL OR start_date <= end_date)
);

-- 4. Backfill query for actors_history_scd
WITH yearly_status AS (
    SELECT
        a.actorid,
        a.actor_name,
        CASE
            WHEN avg_rating > 8 THEN 'star'
            WHEN avg_rating > 7 THEN 'good'
            WHEN avg_rating > 6 THEN 'average'
            ELSE 'bad'
        END as quality_class,
        CASE WHEN film_count > 0 THEN TRUE ELSE FALSE END as is_active,
        make_date(year, 1, 1) as status_date
    FROM (
        SELECT
            actorid,
            actor,
            year,
            COUNT(*) as film_count,
            AVG(rating) as avg_rating
        FROM actor_films
        GROUP BY actorid, actor, year
    ) a
),
status_changes AS (
    SELECT
        actorid,
        actor_name,
        quality_class,
        is_active,
        status_date as start_date,
        LEAD(status_date) OVER (
            PARTITION BY actorid
            ORDER BY status_date
        ) as end_date
    FROM yearly_status
)
INSERT INTO actors_history_scd (
    actorid,
    actor_name,
    quality_class,
    is_active,
    start_date,
    end_date,
    is_current
)
SELECT
    actorid,
    actor_name,
    quality_class,
    is_active,
    start_date,
    CASE
        WHEN end_date IS NULL THEN NULL
        ELSE end_date - INTERVAL '1 day'
    END as end_date,
    CASE WHEN end_date IS NULL THEN TRUE ELSE FALSE END as is_current
FROM status_changes;

-- 5. Incremental query for actors_history_scd
WITH new_status AS (
    SELECT
        a.actorid,
        a.actor_name,
        a.quality_class,
        a.is_active,
        CURRENT_DATE as status_date
    FROM actors a
),
current_records AS (
    SELECT *
    FROM actors_history_scd
    WHERE is_current = TRUE
),
status_changes AS (
    SELECT 
        ns.actorid,
        ns.actor_name,
        ns.quality_class,
        ns.is_active
    FROM new_status ns
    JOIN current_records cr ON ns.actorid = cr.actorid
    WHERE ns.quality_class != cr.quality_class
    OR ns.is_active != cr.is_active
)
UPDATE actors_history_scd
SET 
    end_date = CURRENT_DATE - INTERVAL '1 day',
    is_current = FALSE
WHERE actorid IN (SELECT actorid FROM status_changes)
AND is_current = TRUE;

INSERT INTO actors_history_scd (
    actorid,
    actor_name,
    quality_class,
    is_active,
    start_date,
    end_date,
    is_current
)
SELECT 
    actorid,
    actor_name,
    quality_class,
    is_active,
    CURRENT_DATE,
    NULL,
    TRUE
FROM status_changes;