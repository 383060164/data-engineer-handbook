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