--[[
function OnModPreInit()
end
function OnModInit()
end
function OnModPostInit()
end
]]--

dofile_once("mods/damagelog/files/utils.lua")

function dump(o)
	if type(o) == 'table' then
	   local s = '{ '
	   for k,v in pairs(o) do
		  if type(k) ~= 'number' then k = '"'..k..'"' end
		  s = s .. '['..k..'] = ' .. dump(v) .. ','
	   end
	   return s .. '} '
	else
	   return tostring(o)
	end
 end

local gusgui = dofile_once("mods/damagelog/gusgui/Gui.lua").gusgui()
local Gui = gusgui.Create()

local damage_callback_added = false
local display_gui = true

function OnWorldPostUpdate()
	-- TODO: This only works in beta! No similar methods appear to exist outside of beta as of 2024-04-06

	-- Left Control + E
	if InputIsKeyDown(224) and InputIsKeyJustDown(8) then
		display_gui = not display_gui
	end

	if display_gui then
		Gui:Render()
	end
end

-- TODO: Remove damage_callback_added and instead check whether the player entity actually has the correct LuaComponent
function OnPlayerSpawned(player_entity)
	if damage_callback_added then
		log("!!!!!!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called even though we have added the callback, IGNORING")
		return
	end

	if player_entity == nil then
		log("!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called BUT player_unit not found!!!")
		return
	end

	log("!!!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called successfully, adding damage.lua callback!")

	EntityAddComponent(player_entity, "LuaComponent", {
		script_damage_received = "mods/damagelog/files/damage.lua"
	})
	damage_callback_added = true

	local VLayout = gusgui.Elements.VLayout({
		margin = {top = 47, left = 20, right = 0, bottom = 0},
		id = "TextContainer",
	})
	Gui:AddElement(VLayout)
	VLayout:AddChild(gusgui.Elements.Text({
		id = "SomeText",
		text = "Hello, World!",
		drawBorder = true,
		drawBackground = true,
	}))
	local HLayout = gusgui.Elements.HLayout({
		margin = 0,
		id = "HLayout",
	})
	VLayout:AddChild(HLayout)

	HLayout:AddChild(gusgui.Elements.Text({id = "TextA", text = "ABC", drawBorder = true, drawBackground = true}))
	HLayout:AddChild(gusgui.Elements.Text({id = "TextD", text = "DEF", drawBorder = true, drawBackground = true}))
	HLayout:AddChild(gusgui.Elements.Text({id = "TextG", text = "GHI", drawBorder = true, drawBackground = true}))
end
