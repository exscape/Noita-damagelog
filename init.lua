local Utils = dofile_once("mods/damagelog/files/utils.lua")
local List = Utils.List
dofile_once("mods/damagelog/files/damage.lua")

local imgui = load_imgui({version="1.17.0", mod="damagelog"})

-- State that can't be affected by the player
local initial_clear_completed = false
local last_imgui_warning_time = -3
local player_spawn_time = 0

-- The processed version of the damage data, i.e. formatted strings for the GUI
local gui_data = List.new()

-- TEMPORARY settings, reset on restart
-- Will be removed/reworked to be persistent.
local max_damage_entries = 200 -- TODO: what's a reasonable limit?
local auto_size_columns = true
local alternate_row_colors = false
local show_grid_lines = true
local foreground_opacity = 0.7
local background_opacity = 0.1
local max_rows_to_show = 10
local display_gui = true

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

function draw_gui()
	if not display_gui or not imgui then
		return
	end

	local window_flags = imgui.WindowFlags.AlwaysAutoResize
--	imgui.PushStyleColor(imgui.Col.WindowBg, 0, 0, 0, background_opacity)
	imgui.SetNextWindowBgAlpha(background_opacity)
	imgui.PushStyleVar(imgui.StyleVar.WindowPadding, 0, 0)
	imgui.PushStyleColor(imgui.Col.Text, 1, 1, 1, foreground_opacity)

	-- if window_status_changed and not display_gui and ... first time closing ...
	-- show help
	window_shown, display_gui = imgui.Begin("Damage log", display_gui, window_flags)

	if not window_shown then
		-- Window is collapsed
		imgui.PopStyleVar()
		imgui.PopStyleColor()
		return
	end

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

	if List.length(gui_data) == 0 then
		imgui.TableNextRow()

		imgui.TableNextColumn()
		imgui.Text("Hitless")
		imgui.TableNextColumn()
		imgui.Text(" ")
		imgui.TableNextColumn()
		imgui.Text(" ")
		imgui.TableNextColumn()
		imgui.Text(" ")
		imgui.TableNextColumn()
		imgui.Text(format_time(player_spawn_time))
	end

	local first_index
	if List.length(gui_data) <= max_rows_to_show then
		first_index = gui_data.first
	else
		first_index = gui_data.last - max_rows_to_show + 1
	end

	for row = first_index, gui_data.last do
		imgui.TableNextRow()

		imgui.TableNextColumn()
		imgui.Text(gui_data[row].source)

		imgui.TableNextColumn()
		imgui.Text(gui_data[row].type)

		imgui.TableNextColumn()
		local is_healing, damage = unpack(gui_data[row].damage)
		if is_healing then
			imgui.TextColored(0.25, 0.8, 0.25, 1.0, damage)
		else
			imgui.Text(damage)
		end

		imgui.TableNextColumn()
		imgui.Text(gui_data[row].hp)

		imgui.TableNextColumn()
		imgui.Text(format_time(gui_data[row].time))
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

		_, foreground_opacity = imgui.SliderFloat("Foreground opacity (text etc)", foreground_opacity, 0.1, 1.0)
		_, background_opacity = imgui.SliderFloat("Background opacity", background_opacity, 0.0, 1.0)

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
	imgui.PopStyleColor()
	imgui.PopStyleVar()
end

--- Convert the damage data to what we want to display.
--- This is not done every frame for performance reasons, but rather when the data has changed.
--- If e.g. on fire it WILL currently update every frame, however, since the damage data changes every frame.
function update_gui_data()
	local raw_damage_data = load_damage_data()

	if List.length(raw_damage_data) < 1 then
		error("damagelog: update_gui_data called with no new data!")
		return
	end

	-- Since damage.lua removes all previously read data prior to sending a new batch,
	-- we want to process everything we just received, and don't need to perform any
	-- kinds of checks here.
	for i = raw_damage_data.first, raw_damage_data.last do
		local damage_entry = raw_damage_data[i]

		local source = damage_entry.source
		local type = damage_entry.type
		if source:sub(1, 1) == '$' then source = GameTextGet(source) or "Unknown" end
		if type:sub(1, 1) == '$' then type = GameTextGet(type) or "Unknown" end

		List.pushright(gui_data, {
			source = source,
			type = type,
			damage = { damage_entry.damage < 0, string.format("%.0f", damage_entry.damage) },
			hp = format_hp(damage_entry.hp),
			time = math.floor(damage_entry.time), -- Formatted on display. floor() to make them all update in sync
			id = damage_entry.id
		})

		log("update_gui_data: received damage: source=" .. source .. ", damage=" .. tostring(damage_entry.damage))
	end

	-- Clean up excessive entries
	while List.length(gui_data) > max_damage_entries do
		List.popleft(gui_data)
	end
end

function OnWorldPostUpdate()
	if not initial_clear_completed then
		-- Cleared for now to prevent serialization bugs to carry over between restarts.
		-- This is called BEFORE OnWorldInitialized, where I initially tried to put it,
		-- so while it sucks to check every single frame, I see no other option.
		-- The OnMod*Init methods are called too early; GlobalSetValue isn't available yet.
		-- TODO: If this is left out, the "time" column needs fixing!
		-- TODO: Time is currently stored relative to the elapsed time since load, which of course
		-- TODO: resets on load, so the times will be all wrong.
		local empty_list = safe_serialize(List.new())
		GlobalsSetValue("damagelog_damage_data", empty_list)
		GlobalsSetValue("damagelog_highest_id_written", "0")
		initial_clear_completed = true
	end

	if not imgui then
		-- Not sure how else to handle this. Spam warnings often if imgui is not available, since the mod will be useless.
		local current_time = GameGetRealWorldTimeSinceStarted()
		if current_time - last_imgui_warning_time > 5 then
			GamePrint("damagelog: ImGui not available! Ensure NoitaDearImGui mod is installed, active, and ABOVE this mod in the mod list!")
			last_imgui_warning_time = current_time
		end
	end

	-- NOTE: This requires Noita beta OR a newer build.
	-- As of this writing (2024-04-08) the main branch was updated to have these methods *today*.
	-- Default keys are Left Control + E
	if InputIsKeyDown(224) and InputIsKeyJustDown(8) then
		display_gui = not display_gui
	end

	local highest_id_read = 0
	if not List.isempty(gui_data) then
		highest_id_read = List.peekright(gui_data).id
	end

	local highest_id_written = tonumber(GlobalsGetValue("damagelog_highest_id_written", "0"))

	-- Recalculate at least once a second, since we need to update the time column
	if highest_id_written > highest_id_read then
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

	player_spawn_time = GameGetRealWorldTimeSinceStarted()
end