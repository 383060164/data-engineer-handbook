insert into vertices 
select game_id as identifier,
'game'::vertex_type as type,
json_build_object(
'pts_home', pts_home ,
'pts_away', pts_away ,
'wining_team', case when home_team_wins  =1 then home_team_id else visitor_team_id end
) as properties
from games;