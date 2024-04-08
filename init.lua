dofile_once("mods/damagelog/files/utils.lua")
dofile_once("mods/damagelog/files/damage.lua")

local display_gui = true

-- NOTE: also needs to be changed in damage.lua.
-- Might be changed to a proper setting soon. As of this writing the new UI is not even implemented.
local num_rows = 10

-- TODO: remove unless used in ImGui too
local WIDTH_SOURCE = 80
local WIDTH_TYPE = 60
local WIDTH_DAMAGE = 35
local WIDTH_HP = 40
local WIDTH_TIME = 40

-- A copy of the data from damage.lua, untouched
local raw_damage_data = {}

-- The processed version of the damage data, i.e. formatted strings for the GUI
-- Uses the indices below.
local gui_data = {}

-- Indices for gui_data
local SOURCE = 1
local TYPE = 2
local DAMAGE = 3
local HP = 4
local TIME = 5
local HIDDEN = 6

local latest_update_frame = -1

function format_time(time)
	local current_time = GameGetRealWorldTimeSinceStarted()
	local diff = current_time - time
	if diff < 0 then
		return "future"
	elseif diff < 0.8 then
		return "now"
	elseif diff < 60 then
		return string.format("%.0fs", diff)
	else
		local min, sec = math.floor(diff / 60), math.floor(diff % 60)
		return string.format("%.0fm %.0fs", min, sec)
	end
end

 function format_hp(hp)
	if hp >= 1000000 then
		hp_format = "%.4G"
	else
		hp_format = "%.0f"
	end

	-- Convert e.g. 1.3E+007 to 1.3E7
	formatted_hp = (string.format(hp_format, hp):gsub("E%+0*", "E"))

	-- Prevent string.format from rounding to 0, no matter how close it is
	if formatted_hp == "0" and hp ~= 0 then
		formatted_hp = "<1"
	end

	return formatted_hp
end

function draw_gui()
	--[[
	local VLayout = gusgui.Elements.VLayout({
		margin = {top = 47, left = 20, right = 0, bottom = 0},
		id = "table",
	})
	Gui:AddElement(VLayout)

	local function createRow(row, num)
		row:AddChild(gusgui.Elements.Text({id = "A" .. tostring(num), text = " ", overrideWidth = WIDTH_SOURCE, drawBorder = true, padding = PADDING, margin = MARGIN}))
		row:AddChild(gusgui.Elements.Text({id = "B" .. tostring(num), text = " ", overrideWidth = WIDTH_TYPE, drawBorder = true, padding = PADDING, margin = MARGIN}))
		row:AddChild(gusgui.Elements.Text({id = "C" .. tostring(num), text = " ", overrideWidth = WIDTH_DAMAGE, drawBorder = true, padding = PADDING, margin = MARGIN}))
		row:AddChild(gusgui.Elements.Text({id = "D" .. tostring(num), text = " ", overrideWidth = WIDTH_HP, drawBorder = true, padding = PADDING, margin = MARGIN}))
		row:AddChild(gusgui.Elements.Text({id = "E" .. tostring(num), text = " ", overrideWidth = WIDTH_TIME, drawBorder = true, padding = PADDING, margin = MARGIN}))

		return row
	end

	local header = gusgui.Elements.HLayout({
		margin = 0,
		id = "headerHLayout",
	})
	VLayout:AddChild(header)
	header:AddChild(gusgui.Elements.Text({id = "HeaderA" .. tostring(num), text = "Source", overrideWidth = WIDTH_SOURCE, drawBorder = true, drawBackground = true, padding = PADDING, margin = MARGIN}))
	header:AddChild(gusgui.Elements.Text({id = "HeaderB" .. tostring(num), text = "Type", overrideWidth = WIDTH_TYPE, drawBorder = true, drawBackground = true, padding = PADDING, margin = MARGIN}))
	header:AddChild(gusgui.Elements.Text({id = "HeaderC" .. tostring(num), text = "Damage", overrideWidth = WIDTH_DAMAGE, drawBorder = true, drawBackground = true, padding = PADDING, margin = MARGIN}))
	header:AddChild(gusgui.Elements.Text({id = "HeaderD" .. tostring(num), text = "HP", overrideWidth = WIDTH_HP, drawBorder = true, drawBackground = true, padding = PADDING, margin = MARGIN}))
	header:AddChild(gusgui.Elements.Text({id = "HeaderE" .. tostring(num), text = "Time", overrideWidth = WIDTH_TIME, drawBorder = true, drawBackground = true, padding = PADDING, margin = MARGIN}))

	for i = 1, 10 do
		local row = gusgui.Elements.HLayout({
			margin = 0,
			hidden = i ~= 10, -- Leave the last (first-used) row visible from the beginning
			id = "HLayout" .. tostring(i),
		})
		VLayout:AddChild(row)
		table.insert(rows, row)
		createRow(row, i)
	end
	--]]
end

--- Convert the damage data to what we want to display.
--- This is not done every frame for performance reasons, but rather when the data has changed.
--- If e.g. on fire it WILL currently update every frame, however, since the damage data changes every frame.
function update_gui_data()
	latest_update_frame = GameGetFrameNum()
	raw_damage_data = load_damage_data()

	for row = num_rows, 1, -1 do
		local iteration = num_rows - row + 1 -- starting at 1, as usual in Lua

		if iteration > List.length(raw_damage_data) then
			return
		end

		local dmg_index = raw_damage_data["last"] - (num_rows - row)
		local d = raw_damage_data[dmg_index]

		-- TODO: limit the length of SOURCE and TYPE if needed for ImGui
		gui_data[row][SOURCE] = d[1]
		gui_data[row][TYPE] = d[2]
		gui_data[row][DAMAGE] = string.format("%.0f", d[3])
		gui_data[row][HP] = format_hp(d[4])
		gui_data[row][TIME] = format_time(d[5])
		gui_data[row][HIDDEN] = false
	end
end

function OnModPreInit()
	for i = 1, num_rows do
		gui_data[i] = {}
		gui_data[i][HIDDEN] = true
	end
end

function OnWorldPostUpdate()
	-- NOTE: This requires Noita beta OR a newer build.
	-- As of this writing (2024-04-08) the main branch was updated to have these methods *today*.
	-- Default keys are Left Control + E
	if InputIsKeyDown(224) and InputIsKeyJustDown(8) then
		display_gui = not display_gui
	end

	if not display_gui then
		return
	end

	-- Recalculate at least once a second, since we need to update the time column
	local latest_data_frame = tonumber(GlobalsGetValue("damagelog_latest_data_frame", "0"))
	if (latest_data_frame >= latest_update_frame) or ((GameGetFrameNum() - latest_update_frame) % 60 == 0) then
		update_gui_data()
	end
end

-- Called by Noita when the player spawns. Must have this name.
function OnPlayerSpawned(player_entity)
	if player_entity == nil then
		log("damagelog: OnPlayerSpawned called, but player_entity not found!")
		return
	end

	-- Check if the LuaComponent already exists.
	-- Contrary to what I expected, it seems to be stored permanently in the save, so
	-- if we use a boolean like damage_component_added, we will still end up with multiple
	-- components across game restarts!
	local components = EntityGetComponent(player_entity, "LuaComponent", "damagelog_damage_luacomponent")

	if components == nil or #components == 0 then
		local lua_component = EntityAddComponent(player_entity, "LuaComponent", {
			script_damage_received = "mods/damagelog/files/damage.lua"
		})
		ComponentAddTag(lua_component, "damagelog_damage_luacomponent")
	end

	-- TODO: remove later if we want this to be stored across sessions.
	-- Cleared for now to prevent serialization bugs to carry over between restarts.
	local empty_list = safe_serialize(List.new())
	GlobalsSetValue("damagelog_damage_data", empty_list)

	initialize_gui()



end
