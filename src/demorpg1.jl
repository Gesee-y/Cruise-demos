include(joinpath("..", "..", "AssetCrates.jl", "src", "AssetCrates.jl"))

using .AssetCrates

include(joinpath("..", "..", "Horizons.jl", "src", "CRHorizons.jl"))
include(joinpath("..", "..", "Cruise.jl", "src", "Cruise.jl"))
include(joinpath("..", "..", "SDLOutdoors.jl", "src", "SDLOutdoors.jl"))
include(joinpath("..", "..", "SDLHorizons.jl", "src", "SDLHorizons.jl"))

using .CRHorizons
using .Cruise
using .Cruise.ODPlugin, .Cruise.HZPlugin
using .SDLOutdoors
using .SDLHorizons

# We create a new app
const app = CruiseApp()
const Close = Ref(false)
const assets = CrateManager()

merge_plugin!(app, ODPLUGIN)
merge_plugin!(app, HZPLUGIN)

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

player_up_anim = [Texture(backend, @crate "..|assets|art|playerGrey_up1.png"::ImageCrate), 
    Texture(backend, @crate "..|assets|art|playerGrey_up2.png"::ImageCrate)]
player_walk_anim = [Texture(backend, @crate "..|assets|art|playerGrey_walk1.png"::ImageCrate), 
    Texture(backend, @crate "..|assets|art|playerGrey_walk2.png"::ImageCrate)]

mutable struct Player
	position::Vec2f
	speed::Int
	collision::Rect2Df
	current_anim::Texture
end

mutable struct PlayerUpdateCap
	current_frame::Int
	current_animation::Vector{Texture}
end

player = Player(Vec2f(240, 360), 400, Rect2Df(0, 0, 20, 30), player_up_anim[1])


id = @gamelogic player_update capability=PlayerUpdateCap(1, player_up_anim) begin
    dt = LOOP_VAR_REF[].delta_seconds
	velocity = iVec2f(IsKeyPressed(win, RIGHT) - IsKeyPressed(win, LEFT), 
		IsKeyPressed(win, DOWN) - IsKeyPressed(win, UP))

    if vnorm(velocity) > 0
	    velocity = iVec2f((vnormalize(velocity)*player.speed)...)
	    player.current_anim = self.capability.current_animation[GDMathLib.wrap(self.capability.current_frame ÷ 10, 1, 2)]
	    self.capability.current_frame += 1
	else
		player.current_anim = self.capability.current_animation[2]
	end

	player.position += velocity*dt
	
	if velocity.y != 0
		self.capability.current_animation = player_up_anim
	elseif velocity.x != 0
		self.capability.current_animation = player_walk_anim
	end

	DrawTexture2D(backend, player.current_anim, Rect2Df(player.position..., 5, 5), 0, (velocity.x < 0, false))
end

@gameloop begin
	app.ShouldClose && shutdown!()
end