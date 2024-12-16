
select * from  player_seasons;

create type season_stats as (
	season INTEGER,
	gp INTEGER,
	pts real,
	reb real,
	ast real
);
 CREATE TABLE players (
     player_name TEXT,
     height TEXT,
     college TEXT,
     country TEXT,
     draft_year TEXT,
     draft_round TEXT,
     draft_number TEXT,
     season_stats season_stats[],
     current_season INTEGER,
     PRIMARY KEY (player_name, current_season)
 );
--select min(season) from player_seasons ps 

insert into players
with yesterday as (
select
	*
from
	players
where
	current_season = 2000 --variable change everytime so it will load, start from 1996 as initial
),
today as (
select
	*
from
	player_seasons
where
	season = 2001)
select
	coalesce(t.player_name,
	y.player_name) as player_name,
	
	coalesce(t.height,
	y.height) as height,
	
	coalesce(t.college,
	y.college) as college,
	
	coalesce(t.country,
	y.country) as country,
	
	coalesce(t.draft_year,
	y.draft_year) as draft_year,
	
	coalesce(t.draft_round,
	y.draft_round) as draft_round,
	coalesce(t.draft_number,
	y.draft_number) as draft_number,
	case
		when y.season_stats is null then array[cast(row(t.season,
		t.gp,
		t.pts,
		t.reb,
		t.ast) as season_stats)]
		--active player then add to season_stats so it won't have nulls if it is null
		when t.season is not null then y.season_stats || array[cast(row(t.season,
		t.gp,
		t.pts,
		t.reb,
		t.ast) as season_stats)]
		else y.season_stats
		--retired player who does not have any seasons
	end as season_stats,
	coalesce(t.season, y.current_season + 1) as current_season
from
	today t
full outer join yesterday y on
	t.player_name = y.player_name
 ;

select * from players
where current_season = 2001
and player_name = 'Michael Jordan';

with unnested as (
select player_name, 
unnest(season_stats)::season_stats as season_stats
from players
where current_season = 2001
--and player_name = 'Michael Jordan'
)
select player_name, 
(season_stats).* --or Using dot notation with table alias:
from unnested;

drop table players;

--add 2 more columns
create type scoring_class as enum('star','good','average','bad');

 CREATE TABLE players (
     player_name TEXT,
     height TEXT,
     college TEXT,
     country TEXT,
     draft_year TEXT,
     draft_round TEXT,
     draft_number TEXT,
     season_stats season_stats[],
     scoring_class scoring_class,
     years_since_last_season INTEGER,
     current_season INTEGER,
     PRIMARY KEY (player_name, current_season)
 );
 

insert into players
with yesterday as (
select
	*
from
	players
where
	current_season = 2000 --variable change everytime so it will load, start from 1996 as initial
),
today as (
select
	*
from
	player_seasons
where
	season = 2001)
select
	coalesce(t.player_name,
	y.player_name) as player_name,
	
	coalesce(t.height,
	y.height) as height,
	
	coalesce(t.college,
	y.college) as college,
	
	coalesce(t.country,
	y.country) as country,
	
	coalesce(t.draft_year,
	y.draft_year) as draft_year,
	
	coalesce(t.draft_round,
	y.draft_round) as draft_round,
	coalesce(t.draft_number,
	y.draft_number) as draft_number,
	case
		when y.season_stats is null then array[cast(row(t.season,
		t.gp,
		t.pts,
		t.reb,
		t.ast) as season_stats)]
	--active player then add to season_stats so it won't have nulls if it is null
	when t.season is not null then y.season_stats || array[cast(row(t.season,
		t.gp,
		t.pts,
		t.reb,
		t.ast) as season_stats)]
	else y.season_stats
	--retired player who does not have any seasons
end as season_stats,
	case
	when t.season is not null
	then 
		case
		when t.pts>20 then 'star'
		when t.pts >15 then 'good'
		when t.pts>10 then 'average'
		else 'bad'
		end :: scoring_class
	else y.scoring_class
end as scoring_class,
	case
	when t.season is not null then 0
	else y.years_since_last_season + 1
end as years_since_last_season,
	coalesce(t.season,
y.current_season + 1) as current_season
from
	today t
full outer join yesterday y on
	t.player_name = y.player_name
 ;
 
select
	*
from
	players
where
	current_season = 2001
	and player_name = 'Michael Jordan';

--most improved player pts
--TAKEAWAY
--AND YOU NOTICE, YOU DONT NEED GROUP BY, IF NOT ACCUMULATED TABLE, YOU WILL NEED! No need to shuffle data, very quick!
select
	player_name,
	(season_stats[1]:: season_stats).pts first_season,
	(season_stats[cardinality(season_stats)]:: season_stats).pts latest_season,
(season_stats[cardinality(season_stats)]:: season_stats).pts
/case 
	when ((season_stats[1]:: season_stats).pts )=0 then 1
	else 
	(season_stats[1]:: season_stats).pts 
end as ratio
from players
where current_season = 2001
and scoring_class = 'star'
order by 4 desc;

