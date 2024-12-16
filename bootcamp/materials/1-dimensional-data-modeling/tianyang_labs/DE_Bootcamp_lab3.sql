CREATE TYPE vertex_type
    AS ENUM('player', 'team', 'game');



CREATE TABLE vertices (
    identifier TEXT,
    type vertex_type,
    properties JSON,
    PRIMARY KEY (identifier, type)
);

CREATE TYPE edge_type AS
    ENUM ('plays_against',
          'shares_team',
          'plays_in',
          'plays_on'
        );
  
CREATE TABLE edges (
    subject_identifier TEXT,
    subject_type vertex_type,
    object_identifier TEXT,
    object_type vertex_type,
    edge_type edge_type,
    properties JSON,
    PRIMARY KEY (subject_identifier,
                subject_type,
                object_identifier,
                object_type,
                edge_type)
);

insert  into vertices 
select game_id as identifier,
'game'::vertex_type as type,
json_build_object(
'pts_home', pts_home ,
'pts_away', pts_away ,
'wining_team', case when home_team_wins  =1 then home_team_id else visitor_team_id end
) as properties
from games;

insert  into vertices
with players_agg as (
select 
player_id as identifier,
max(player_name) as player_name ,
count(1) as number_of_games,
sum(pts) as total_points,
array_agg(distinct team_id) as teams 
from game_details 
group by player_id 
)
select identifier, 
'player'::vertex_type as type,
json_build_object(
'player_name', player_name,
'number_of_games', number_of_games,
'total_points',total_points,
'teams',teams
)
from players_agg;

insert  into vertices
WITH teams_deduped AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY team_id) as row_num
    FROM teams
)
SELECT
       team_id AS identifier,
    'team'::vertex_type AS type,
    json_build_object(
        'abbreviation', abbreviation,
        'nickname', nickname,
        'city', city,
        'arena', arena,
        'year_founded', yearfounded
        )
FROM teams_deduped
WHERE row_num = 1;

select type,count(1) from vertices 
group by 1;

select * from vertices 
where type = 'player';

INSERT INTO edges
WITH deduped AS (
    SELECT *, row_number() over (PARTITION BY player_id, game_id) AS row_num
    FROM game_details
)
SELECT
    player_id AS subject_identifier,
    'player'::vertex_type as subject_type,
    game_id AS object_identifier,
    'game'::vertex_type AS object_type,
    'plays_in'::edge_type AS edge_type,
    json_build_object(
        'start_position', start_position,
        'pts', pts,
        'team_id', team_id,
        'team_abbreviation', team_abbreviation
        ) as properties
FROM deduped
WHERE row_num = 1;

select edge_type,count(1) from edges 
group by 1;

select 
v.properties->>'player_name',
max(cast(e.properties->>'pts'as INTEGER))
from vertices v  join edges e 
on e.subject_identifier = v.identifier
and e.subject_type = v.type
group by 1
order by 2 desc;


insert into edges 
	with deduped as (
	select
		*,
		row_number() over (partition by player_id,
		game_id) as row_num
	from
		game_details)
,
	filtered as
(
	select
		*
	from
		deduped
	where
		row_num = 1
),
	aggregated as (
	select
		f1.player_id as subject_player_id,
		max(f1.player_name) as subject_player_name,
		f2.player_id as object_player_id,
		max(f2.player_name) as object_player_name,
		case
			when f1.team_abbreviation = f2.team_abbreviation then 'shares_team'::edge_type
			else 'plays_against' ::edge_type
		end as edge_type,
		count(1) as num_games,
		sum(f1.pts) as subject_points,
		sum(f2.pts) as object_points
		--f1.team_abbreviation, f2.team_abbreviation
	from
		filtered f1
	join filtered f2 
on
		f1.game_id = f2.game_id
		and f1.player_name <> f2.player_name
		--just want the single sid
	where
		f1.player_id >f2.player_id
		--This is a common technique in graph processing to avoid duplicate edges when the relationship direction doesn't matter.
	group by
		f1.player_id,
		f2.player_id,
		case
			when f1.team_abbreviation = f2.team_abbreviation then 'shares_team'::edge_type
			else 'plays_against' ::edge_type
		end
)
select
	subject_player_id as subject_identifier,
	'player'::vertex_type as subject_type,
	object_player_id as object_identifier,
	'player'::vertex_type as object_type,
	edge_type as edge_type,
	json_build_object(
'num_games',
	num_games,
	'subject_points',
	subject_points,
	'object_points',
	object_points)
from
	aggregated;
	
select 
v.properties ->>'player_name',
e.object_identifier,
cast(v.properties ->>'number_of_games'as real)/
case when cast(v.properties ->>'total_points'as real)=0 then 1 else 
cast(v.properties ->>'total_points'as real)
end,
e.properties->>'subject_points',
e.properties->>'num_games'
from vertices v join edges e
on v.identifier  = e.subject_identifier 
and v.type = e.subject_type 
where e.object_type ='player'::vertex_type;