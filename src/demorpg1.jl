include(joinpath("..", "..", "AssetCrates.jl", "src", "AssetCrates.jl"))

using .AssetCrates

include(joinpath("..", "..", "Horizons.jl", "src", "CRHorizons.jl"))
include(joinpath("..", "..", "Cruise.jl", "src", "Cruise.jl"))
include(joinpath("..", "..", "SDLOutdoors.jl", "src", "SDLOutdoors.jl"))
include(joinpath("..", "..", "SDLHorizons.jl", "src", "SDLHorizons.jl"))

using .CRHorizons
using .Cruise
using .Cruise.ODPlugin, .Cruise.HZPlugin, .Cruise.TimerPlugin
using .SDLOutdoors
using .SDLHorizons

abstract type AbstractBody end

# We create a new app
const app = CruiseApp()
const Close = Ref(false)
const assets = CrateManager()

merge_plugin!(app, ODPLUGIN)
merge_plugin!(app, HZPLUGIN)
merge_plugin!(app, TIMERPLUGIN)

@InputMap UP("UP", "W")
@InputMap LEFT("LEFT", "A")
@InputMap DOWN("DOWN", "S")
@InputMap RIGHT("RIGHT", "D")

window_size = iVec2(480, 720)

AssetCrates.getmanager() = assets

# Initialise SDL style window with a SDL renderer
const win = CreateWindow(SDLStyle, "Example", window_size...)
const backend = InitBackend(SDLRender, GetStyle(win).window, window_size...; bgcol=GRAY)
const screen = get_texture(backend.viewport.screen)
bgcolors = HZPlugin.MANAGER.other


########################################################## Game code ############################################

const MONSTER_SPAWN_RATE = 0.5
player_score = 0

player_up_anim = [Texture(backend, @crate "..|assets|art|playerGrey_up1.png"::ImageCrate), 
    Texture(backend, @crate "..|assets|art|playerGrey_up2.png"::ImageCrate)]
player_walk_anim = [Texture(backend, @crate "..|assets|art|playerGrey_walk1.png"::ImageCrate), 
    Texture(backend, @crate "..|assets|art|playerGrey_walk2.png"::ImageCrate)]

enemy_flying_anim = [Texture(backend, @crate "..|assets|art|enemyFlyingAlt_1.png"::ImageCrate), 
    Texture(backend, @crate "..|assets|art|enemyFlyingAlt_2.png"::ImageCrate)]
enemy_swimming_anim = [Texture(backend, @crate "..|assets|art|enemySwimming_1.png"::ImageCrate), 
    Texture(backend, @crate "..|assets|art|enemySwimming_2.png"::ImageCrate)]
enemy_walking_anim = [Texture(backend, @crate "..|assets|art|enemyWalking_1.png"::ImageCrate), 
    Texture(backend, @crate "..|assets|art|enemyWalking_2.png"::ImageCrate)]

game_bodies = AbstractBody[]

##################################################### PATH STUFFS ###############################################

mutable struct Path
	points::Vector{Vec2f}
end

path = Path(Vec2f[Vec2f(0,0), Vec2f(window_size.x, 0), Vec2f(window_size...), Vec2f(0, window_size.y)])

###################################################### Player Stuff #############################################

@Notifyer PLAYER_COLLISION_ENTER(body)
@Notifyer PLAYER_COLLISION_EXIT(body)
@Notifyer BODY_SCREEN_EXITED(body)

mutable struct Player <: AbstractBody
	position::Vec2f
	speed::Int
	collision::Rect2Df
	current_anim::Texture
end

mutable struct Enemy{T} <: AbstractBody
	position::Vec2f
	speed::Vec2f
	collision::Rect2Df
	current_anim::Texture
end

mutable struct PlayerUpdateCap
	current_frame::Int
	current_animation::Vector{Texture}
	flip::NTuple{2, Bool}
end

mutable struct PlayerCollisionCap
	colliders::Dict{AbstractBody, Int}

	## Constructor

	PlayerCollisionCap() = new(Dict{AbstractBody, Int}())
end

getrect(b::AbstractBody) = b.collision
render(e::Enemy) = DrawTexture2D(backend, e.current_anim, Rect2Df(e.position..., 3, 3))

function spawn_enemy()
	timer = addtimer!(MONSTER_SPAWN_RATE)
	ontimeout(spawn_enemy, timer)
    
    i = rand(1:length(path.points))
    p1, p2 = path.points[i], path.points[wrap(i+1, 1, length(path.points))]
    x,y = rand(min(p1.x, p2.x):max(p1.x, p2.x)), rand(min(p1.y, p2.y):max(p1.y, p2.y))
	velocity = vrotate(iVec2f(1, 0), acos(x/sqrt(x^2+y^2)) + pi/2) * rand(100:600)
	push!(game_bodies, Enemy{:ghost}(Vec2f(x,y), velocity, Rect2Df(0,0,30,30), enemy_flying_anim[1]))
end

proc_id = @gamelogic process_enemy begin
	for body in game_bodies
		body.position += body.velocity
	end
end

ren_id = @gamelogic render_enemy begin
	for body in game_bodies
		render(body)
	end
end

add_dependency!(app.plugins, proc_id, ren_id)

player = Player(Vec2f(240, 360), 400, Rect2Df(0, 0, 20, 30), player_up_anim[1])

col_id = @gamelogic player_collision capability=PlayerCollisionCap() begin
    for body in game_bodies
    	does_intersect = overlapping(getrect(body), player.collision)
    	if does_intersect && !haskey(self.capability.colliders, body)
    		self.capability.colliders[body] = 0
    		PLAYER_COLLISION_ENTER.emit = body
    	elseif !does_intersect && haskey(self.capability.colliders, body)
    		delete!(self.capability.colliders, body)
    		PLAYER_COLLISION_EXIT.emit = body
    	end

    	if (getrect(body).x < -getrect(body).w || getrect(body).x > window_size.x) || 
    		(getrect(body).y < -getrect(body).h || getrect(body).y > window_size.y)

    		BODY_SCREEN_EXITED.emit = body
    	end
    end
end

EventNotifiers.connect(PLAYER_COLLISION_ENTER) do body
	disable_system(col_id)
	disable_system(ren_id)
	disable_system(proc_id)
	println("You died bozos.")
	clear!(TimerPlugin.TM)
end

EventNotifiers.connect(BODY_SCREEN_EXITED) do body
	for i in eachindex(game_bodies)
		b = game_bodies[i]
		if b == body
			game_bodies[i] = game_bodies[end]
			pop!(game_bodies)
			return
		end
	end
end

spawn_enemy()

################################################### GAME LOGICS #################################################

id = @gamelogic player_update capability=PlayerUpdateCap(1, player_up_anim, (false, false)) begin
    dt = LOOP_VAR_REF[].delta_seconds
	velocity = iVec2f(IsKeyPressed(win, RIGHT) - IsKeyPressed(win, LEFT), 
		IsKeyPressed(win, DOWN) - IsKeyPressed(win, UP))

    if vnorm(velocity) > 0
	    velocity = iVec2f((vnormalize(velocity)*player.speed)...)
	    player.current_anim = self.capability.current_animation[GDMathLib.wrap(self.capability.current_frame ÷ 10, 1, 2)]
	    self.capability.current_frame += 1
	    self.capability.flip = (velocity.x < 0, false)
	else
		player.current_anim = self.capability.current_animation[2]
	end

	player.position += velocity*dt
	
	if velocity.y != 0
		self.capability.current_animation = player_up_anim
	elseif velocity.x != 0
		self.capability.current_animation = player_walk_anim
	end

end

id2 = @gamelogic player_render begin
    hasfaileddeps(self) && error("Error while rendering the player. Could not been updated properly")
    player_update = self.deps[GameCode{:player_update}]
	DrawTexture2D(backend, player.current_anim, Rect2Df(player.position..., 5, 5), 0, player_update.flip)
end

add_dependency!(app.plugins, id, id2)

@gameloop begin
	player_score += LOOP_VAR_REF[].frame_idx % 60 == 0
	app.ShouldClose && shutdown!()
end