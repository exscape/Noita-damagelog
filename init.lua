dofile_once("mods/damagelog/files/utils.lua")
dofile_once("mods/damagelog/files/damage.lua")
local gusgui = dofile_once("mods/damagelog/gusgui/Gui.lua").gusgui()
local Gui = nil

local display_gui = true

local WIDTH_SOURCE = 80
local WIDTH_TYPE = 60
local WIDTH_DAMAGE = 35
local WIDTH_HP = 40
local WIDTH_TIME = 40
local PADDING = { left = 3, right = 3, top = 2, bottom = 2}
local MARGIN = 0

-- Indices for rows[x].children for each column
local SOURCE = 1
local TYPE = 2
local DAMAGE = 3
local HP = 4
local TIME = 5

local rows = {}
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

function initialize_gui()
	if Gui ~= nil then
		Gui:Destroy()
	end

	Gui = gusgui.Create()
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
end

function update_gui()
	latest_update_frame = GameGetFrameNum()
	local damage_data = load_damage_data()

	for row = 10, 1, -1 do
		local iteration = 10 - row + 1 -- starting at 1, as usual in Lua
		local dmg_index = damage_data["last"] - (10 - row)

		if iteration > List.length(damage_data) then
			return
		end

		-- Entity / source
		-- TODO: limit the length to avoid messy layout from certain enemies
		rows[row].children[SOURCE].config.text.value = damage_data[dmg_index][1]

		-- Damage type
		rows[row].children[TYPE].config.text.value = damage_data[dmg_index][2]

		-- Damage
		rows[row].children[DAMAGE].config.text.value = string.format("%.0f", damage_data[dmg_index][3])

		-- HP after
		hp_after = damage_data[dmg_index][4]

		if hp_after >= 1000000 then
			hp_format = "%.4G"
		else
			hp_format = "%.0f"
		end
		-- Convert e.g. 1.3E+007 to 1.3E7
		formatted_hp = (string.format(hp_format, hp_after):gsub("E%+0*", "E"))

		if formatted_hp == "0" then
			formatted_hp = "1"
		end
		rows[row].children[HP].config.text.value = formatted_hp

		-- Time
		rows[row].children[TIME].config.text.value = format_time(damage_data[dmg_index][5])

		rows[row].config.hidden = false
	end
end

function OnWorldPostUpdate()
	-- TODO: This only works in beta! No similar methods appear to exist outside of beta as of 2024-04-06
	-- Left Control + E
	if InputIsKeyDown(224) and InputIsKeyJustDown(8) then
		display_gui = not display_gui
	end

	if Gui == nil or not display_gui then
		return
	end

	local latest_data_frame = tonumber(GlobalsGetValue("damagelog_latest_data_frame", "0"))
	if (latest_data_frame >= latest_update_frame) or (GameGetFrameNum() % 60 == 0) then
		update_gui()
	end

	Gui:Render()
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
