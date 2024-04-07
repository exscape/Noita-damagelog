dofile_once("mods/damagelog/files/utils.lua")
dofile_once("mods/damagelog/files/damage.lua")
local gusgui = dofile_once("mods/damagelog/gusgui/Gui.lua").gusgui()
local Gui = nil

local display_gui = true

local WIDTH_SOURCE = 70
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

function FormatTimeAgo(time)
	local current_time = GameGetRealWorldTimeSinceStarted()
	local diff = current_time - time
	if diff < 0 then
		return "future"
	elseif diff < 0.8 then
		return "now"
	elseif diff < 60 then
		return string.format("%.0fs", diff)
	else
		local min, sec = math.floor(diff / 60), diff % 60
		return string.format("%.0fm %.0fs", min, sec)
	end
end

function CreateGUI()
	if Gui ~= nil then
		Gui:Destroy()
	end

	Gui = gusgui.Create()
	local VLayout = gusgui.Elements.VLayout({
		margin = {top = 47, left = 20, right = 0, bottom = 0},
		id = "table",
	})
	Gui:AddElement(VLayout)

	local function createRow(HLayout, num)
		HLayout:AddChild(gusgui.Elements.Text({id = "A" .. tostring(num), text = "A" .. tostring(num), overrideWidth = WIDTH_SOURCE, drawBorder = true, padding = PADDING, margin = MARGIN}))
		HLayout:AddChild(gusgui.Elements.Text({id = "B" .. tostring(num), text = "B" .. tostring(num), overrideWidth = WIDTH_TYPE, drawBorder = true, padding = PADDING, margin = MARGIN}))
		HLayout:AddChild(gusgui.Elements.Text({id = "C" .. tostring(num), text = "C" .. tostring(num), overrideWidth = WIDTH_DAMAGE, drawBorder = true, padding = PADDING, margin = MARGIN}))
		HLayout:AddChild(gusgui.Elements.Text({id = "D" .. tostring(num), text = "D" .. tostring(num), overrideWidth = WIDTH_HP, drawBorder = true, padding = PADDING, margin = MARGIN}))
		HLayout:AddChild(gusgui.Elements.Text({id = "E" .. tostring(num), text = tostring(Random(1, 300)), overrideWidth = WIDTH_TIME, drawBorder = true, padding = PADDING, margin = MARGIN}))

		return HLayout
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
		local HLayout = gusgui.Elements.HLayout({
			margin = 0,
			id = "HLayout" .. tostring(i),
--			hidden = i > 6,
--			drawBackground = true,
--			overrideWidth = WIDTH_TABLE -- Needed for alignment, otherwise each row is as short as it can be
		})
		VLayout:AddChild(HLayout)
		table.insert(rows, HLayout)
		createRow(HLayout, i)
	end
end

function UpdateGUI()
	latest_update_frame = GameGetFrameNum()
	local damage_data = load_damage_data()

	local damage_count = #damage_data
	-- log("damage_count in UpdateGUI is " .. tostring(damage_count))
	for row=10,1,-1 do
		local i = 10 - row + 1
		if i > damage_count then
--			log("exiting loop, i > damage_count: " .. tostring(i) .. " > " .. tostring(damage_count))
			return
		end

	--	log("damage_count=" .. tostring(damage_count) .. ", row=" .. tostring(row) .. ", i=" .. tostring(i) .. ", accessing damage_data[" .. tostring(damage_count - i + 1) .. "]")

		-- Entity / source
		rows[row].children[SOURCE].config.text.value = damage_data[damage_count - i + 1][1]

		-- Damage type
		rows[row].children[TYPE].config.text.value = damage_data[damage_count - i + 1][2]

		-- Damage
		rows[row].children[DAMAGE].config.text.value = string.format("%.0f", damage_data[damage_count - i + 1][3])

		-- HP after
		hp_after = damage_data[damage_count - i + 1][4]

		if hp_after >= 1000000 then
			hp_format = "%.4G"
		else
			hp_format = "%.0f"
		end
		-- Convert e.g. 1.3E+007 to 1.3E7
		formatted_hp = (string.format(hp_format, hp_after):gsub("E%+0*", "E"))

		if formatted_hp == "0"
			formatted_hp = "1"
		end
		rows[row].children[HP].config.text.value = formatted_hp

		-- Time
		rows[row].children[TIME].config.text.value = FormatTimeAgo(damage_data[damage_count - i + 1][5])
	end
end

function OnWorldPostUpdate()
	-- TODO: This only works in beta! No similar methods appear to exist outside of beta as of 2024-04-06

	-- Left Control + E
	if InputIsKeyDown(224) and InputIsKeyJustDown(8) then
		display_gui = not display_gui
	end

	if not (display_gui and Gui ~= nil) then
		return
	end

	local latest_data_frame = tonumber(GlobalsGetValue("damagelog_latest_data_frame", "0"))
	if (latest_data_frame >= latest_update_frame) or (GameGetFrameNum() % 60 == 0) then
		UpdateGUI()
	end

	Gui:Render()
end

function OnPlayerSpawned(player_entity)
	if player_entity == nil then
		log("!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called BUT player_unit not found!!!")
		return
	end

	-- Check if the component already exists
	-- Contrary to what I expected, it seems to be stored permanently in the save, so
	-- if we use a boolean like damage_component_added, we will still end up with multiple
	-- components across game restarts!

	local components = EntityGetComponent(player_entity, "LuaComponent", "damagelog_damage_luacomponent")

	if components == nil or #components == 0 then
		log("!!!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called successfully, adding damage.lua callback!")

		local lua_component = EntityAddComponent(player_entity, "LuaComponent", {
			script_damage_received = "mods/damagelog/files/damage.lua"
		})
		ComponentAddTag(lua_component, "damagelog_damage_luacomponent")
	else
		log("!!!!!!!!!!!!!!!!! OnPlayedSpawned called, but our LuaComponent already exists! Not adding a second one.")
	end

	-- TODO: remove later if we want this to be stored across sessions
	-- Cleared for now to prevent serialization bugs to carry over between restarts
	GlobalsSetValue("damagelog_damage_data", "{}")

	CreateGUI()


end
