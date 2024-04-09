local Utils = dofile_once("mods/damagelog/files/utils.lua")
local List = Utils.List
dofile_once("mods/damagelog/files/damage.lua")

local imgui = load_imgui({version="1.17.0", mod="damagelog"})

-- NOTE: also needs to be changed in damage.lua.
-- Might be changed to a proper setting soon. As of this writing the new UI is not even implemented.
local num_rows = 10

-- A copy of the data from damage.lua, untouched
local raw_damage_data = List.new()

-- The processed version of the damage data, i.e. formatted strings for the GUI
-- Uses the indices below.
local gui_data = {}

local latest_update_frame = -1
local display_gui = true

-- TEMPORARY settings, reset on restart
-- Will be removed/reworked to be persistent.
local auto_size_columns = true
local alternate_row_colors = false
local show_grid_lines = true

function format_time(time)
	local current_time = GameGetRealWorldTimeSinceStarted()
	local diff = current_time - time
	if diff < 0 then
		return "?"
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

	-- Format, and convert e.g. 1.3E+007 to 1.3E7
	formatted_hp = (string.format(hp_format, hp):gsub("E%+0*", "E"))

	-- Prevent string.format from rounding to 0... in most cases
	if formatted_hp == "0" and hp > 0 then
		formatted_hp = string.format("%.03f", hp)
	end

	return formatted_hp
end

local collapsed = false

function draw_gui()
	if not imgui then return end


	if not display_gui then
		return
	end

	local window_flags = imgui.WindowFlags.AlwaysAutoResize
	window_shown, display_gui = imgui.Begin("Damage log", display_gui, window_flags)
	log("not_collapsed: " .. tostring(window_shown))

	if not window_shown then
		-- Window is collapsed
		return
	end

--	if window_status_changed and not display_gui and ... first time closing ...
--if imgui.Begin("Damage log", display_gui, window_flags) then
	imgui.PushStyleVar(imgui.StyleVar.CellPadding, 7, 3)

	local table_flags = bit.bor(
		imgui.TableFlags.Reorderable,
		imgui.TableFlags.Hideable,
		imgui.TableFlags.BordersOuter,
		choice(not auto_size_columns, imgui.TableFlags.Resizable, 0),
		choice(alternate_row_colors, imgui.TableFlags.RowBg, 0),
		choice(show_grid_lines, imgui.TableFlags.BordersInner, 0)
	)

	imgui.BeginTable("Damage", 5, table_flags)

	-- Column setup + headers
	imgui.TableSetupColumn("Source")
	imgui.TableSetupColumn("Type")
	imgui.TableSetupColumn("Damage")
	imgui.TableSetupColumn("HP")
	imgui.TableSetupColumn("Time")
	imgui.TableHeadersRow()

	for row = 1, math.min(num_rows, List.length(raw_damage_data)) do
		-- The data is stored such that the most recent data is at index num_rows,
		-- but we need to draw it from the top. However, if there are fewer than
		-- num_rows (usually 10) hits, indices below 10 may be nil, so in that case
		-- we need to look at a larger index.
		local data_index = row + (num_rows - List.length(raw_damage_data))
		imgui.TableNextRow()

		imgui.TableNextColumn()
		imgui.Text(gui_data[data_index].source)

		imgui.TableNextColumn()
		imgui.Text(gui_data[data_index].type)

		imgui.TableNextColumn()
		local is_healing, damage = unpack(gui_data[data_index].damage)
		if is_healing then
			imgui.TextColored(0.25, 0.8, 0.25, 1.0, damage)
		else
			imgui.Text(damage)
		end

		imgui.TableNextColumn()
		imgui.Text(gui_data[data_index].hp)

		imgui.TableNextColumn()
		imgui.Text(gui_data[data_index].time)
	end

	-- Add popup to right-clicking on any of the columns (except the header)
	local is_any_column_hovered = false
	for column = 1, 5 do
		if bit.band(imgui.TableGetColumnFlags(column - 1), imgui.TableColumnFlags.IsHovered) then
			is_any_column_hovered = true
			break
		end
	end

	imgui.PushID("123")
	if is_any_column_hovered and not imgui.IsAnyItemHovered() and imgui.IsMouseReleased(1) then
		imgui.OpenPopup("SettingsPopup")
	end

	if imgui.BeginPopup("SettingsPopup") then
		imgui.Text("Settings are applied and saved immediately.")

		if imgui.RadioButton("Auto-size columns to fit", auto_size_columns) then auto_size_columns = true end
		if imgui.RadioButton("Manual sizing (click divider + drag). Will remember the user-set sizes.", not auto_size_columns) then auto_size_columns = false end

		_, alternate_row_colors = imgui.Checkbox("Alternate row colors", alternate_row_colors)
		_, show_grid_lines = imgui.Checkbox("Show grid lines", show_grid_lines)

		if imgui.Button("Close") then
			imgui.CloseCurrentPopup()
		end
		imgui.EndPopup()
	end
	imgui.PopID()

	imgui.EndTable()
	imgui.PopStyleVar()
	imgui.End() -- Damage log window
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
		local damage_entry = raw_damage_data[dmg_index]

		local source = damage_entry.source
		local type = damage_entry.type
		if source:sub(1, 1) == '$' then source = GameTextGet(source) or "Unknown" end
		if type:sub(1, 1) == '$' then type = GameTextGet(type) or "Unknown" end
		type = (type:gsub("^%l", string.upper))

		-- TODO: limit the length of SOURCE and TYPE if needed for ImGui
		gui_data[row].source = source
		gui_data[row].type = type
		gui_data[row].damage = { damage_entry.damage < 0, string.format("%.0f", damage_entry.damage) }
		gui_data[row].hp = format_hp(damage_entry.hp)
		gui_data[row].time = format_time(damage_entry.time)
	end
end

function OnModPreInit()
	for i = 1, num_rows do
		gui_data[i] = {}
	end
end

local last_warning_time = -3
function OnWorldPostUpdate()
	if not imgui then
		-- Not sure how else to handle this. Spam warnings often if imgui is not available, since the mod will be useless.
		local current_time = GameGetRealWorldTimeSinceStarted()
		if current_time - last_warning_time > 5 then
			GamePrint("damagelog: ImGui not available! Ensure NoitaDearImGui mod is installed, active, and ABOVE this mod in the mod list!")
			last_warning_time = current_time
		end
	end

	-- NOTE: This requires Noita beta OR a newer build.
	-- As of this writing (2024-04-08) the main branch was updated to have these methods *today*.
	-- Default keys are Left Control + E
	if InputIsKeyDown(224) and InputIsKeyJustDown(8) then
		display_gui = not display_gui
	end

	-- Recalculate at least once a second, since we need to update the time column
	local latest_data_frame = tonumber(GlobalsGetValue("damagelog_latest_data_frame", "0"))
	if latest_data_frame > latest_update_frame or (GameGetFrameNum() - latest_update_frame) >= 60 then
		update_gui_data()
	end

	draw_gui()
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
--	local empty_list = safe_serialize(List.new())
--	GlobalsSetValue("damagelog_damage_data", empty_list)
end
