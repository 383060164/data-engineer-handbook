
create table fct_game_details(
dim_game_date DATE,
dim_season integer,
dim_team_id integer,
dim_player_id integer,
dim_player_name text,
dim_start_position text,
dim_is_playing_at_home boolean,
dim_did_not_play boolean,
dim_did_not_dress boolean,
dim_not_with_team boolean,
m_minutes real,
m_fgm integer,
m_fga integer,
m_fg3m integer,
m_fg3a integer,
m_ftm integer,
m_fta integer,
m_oreb integer,
m_dreb integer,
m_reb integer,
m_ast integer,
m_stl integer,
m_blk integer,
m_turnovers integer,
m_pf integer,
m_pts integer,
m_plus_minus integer,
primary key (dim_game_date,dim_team_id,dim_player_id)
);

insert into fct_game_details
with deduped as (
select 
	g.game_date_est,
	g.season,
	g.home_team_id,
	g.visitor_team_id,
	gd.*,	
	row_number() over (partition by gd.game_id,
	team_id,
	player_id
	--you can use order by in some case
order by
	g.game_date_est
	) as row_num
	--duplicate so it can find out
from
	game_details gd
join games g on
	gd.game_id = g.game_id
--where
--	g.game_date_est = '2016-10-04'
)
select
	game_date_est as dim_game_date,
	----	game_id -- since we already grab the needed details from game and all other info can be derived so we don't need game_id
	season as dim_season,
	team_id as dim_team_id,
	player_id as dim_player_id, 
	player_name as dim_player_name,
	start_position as dim_start_position,
	team_id = home_team_id as dim_is_playing_at_home,
	coalesce(position('DNP' in comment),0)>0 as dim_did_not_play,
	coalesce(position('DND' in comment),0)>0 as dim_did_not_dress,
	coalesce(position('NWT' in comment),0)>0 as dim_not_with_team,
--	comment,-- since we parse everything, we can remove it
	(cast(split_part(min,':',1)as real) +  
	cast(split_part(min,':',2) as real)/60) as m_minutes,
	fgm as m_fgm,
	fga as m_fga,
	fg3m as m_fg3m,
	fg3a as m_fg3a,
	ftm as m_ftm,
	fta as m_fta,
	oreb as m_oreb,
	dreb as m_dreb,
	reb as m_reb,
	ast as m_ast,
	stl as m_stl,
	blk as m_blk,
	"TO" as m_turnovers,
	pf as m_pf,
	pts as m_pts,
	plus_minus as m_plus_minus
from
	deduped
where
	row_num = 1;
	
select * from fct_game_details gd join teams t 
on t.team_id = gd.dim_team_id;

select dim_player_name, 
count(1) as num_games,
count(case when dim_not_with_team then 1 end) as bailed_num,
cast(count(case when dim_not_with_team then 1 end) as real)/cast(count(1) as real) as bailed_pct
from fct_game_details
group by 1
order by 4 desc;