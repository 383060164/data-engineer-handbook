 drop table users_cumulated;
 CREATE TABLE users_cumulated (
     user_id text,--BIGINT,
     -- the list of date in the pas where the user was active
     dates_active DATE[], --this is date array
     -- the current date for the user
     date DATE,
     PRIMARY KEY (user_id, date)
 );

--date list datatype example
WITH yesterday AS (
    SELECT * FROM users_cumulated
    WHERE date = DATE('2023-01-05')
),
    today AS (
          SELECT cast(user_id as text)as user_id ,
                 DATE_TRUNC('day', cast(event_time as timestamp)) AS today_date,
                 COUNT(1) AS num_events FROM events
            WHERE DATE_TRUNC('day', cast(event_time as timestamp)) = DATE('2023-01-06')
            AND user_id IS NOT NULL
         GROUP BY user_id,  DATE_TRUNC('day', cast(event_time as timestamp))
    )
INSERT INTO users_cumulated
--very like the dimensional modeling lab 1 that create a cumulative table
SELECT
       COALESCE(t.user_id, y.user_id),
       COALESCE(y.dates_active,
           ARRAY[]::DATE[])
            || CASE WHEN
                t.user_id IS NOT NULL
                THEN ARRAY[t.today_date]
                ELSE ARRAY[]::DATE[]
                END AS date_list,
       COALESCE(t.today_date, y.date + Interval '1 day') as date
FROm yesterday y
    FULL OUTER JOIN
    today t ON t.user_id = y.user_id;
   
 select * from users_cumulated
WHERE date = DATE('2023-01-05');

with users as (
	select * from users_cumulated 
	where date = date('2023-01-05')
),
series as (
select * from  generate_series(date('2023-01-01'),date('2023-01-31'),interval '1 day') as series_date
),
place_holder_ints as (
--notice difference between cross join and full outer join
--if the dates_active is in the series_date @> means contains
select 
--date - date(series_date), --num of days diff
--case when 
--dates_active @> ARRAY [DATE(series_date)]  then 
--	cast(power(2,32-(date - date(series_date))) as bigint)
--else 0
--end,
--cast(
case when 
dates_active @> ARRAY [DATE(series_date)]  then cast(power(2,32-(date - date(series_date))) as bigint)
else 0
end
--as bit(32)) 
as placeholder_int_value,
* 
from users cross join  series
--where user_id = '4250280751558363600'
)
select 
user_id, 
sum(placeholder_int_value),
cast(cast(sum(placeholder_int_value)as bigint) as bit(32)),
bit_count(cast(cast(sum(placeholder_int_value)as bigint) as bit(32)))  >0 as dim_is_monthly_active,
bit_count(
cast ('11111110000000000000000000000000' as bit (32)) & 
cast(cast(sum(placeholder_int_value)as bigint) as bit(32))
)>0 dim_is_weekly_active,
bit_count(
cast ('10000000000000000000000000000000' as bit (32)) & 
cast(cast(sum(placeholder_int_value)as bigint) as bit(32))
)>0 dim_is_daily_active
from place_holder_ints
group by user_id;
