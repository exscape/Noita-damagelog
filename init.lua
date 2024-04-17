local imgui = load_imgui({version="1.17.0", mod="damagelog"})
local Utils = dofile_once("mods/damagelog/files/utils.lua")
local List = Utils.List
dofile_once('data/scripts/debug/keycodes.lua')

--[[
    Here's a basic overview of how the mod works, for my future self, and others interested.
    Hopefully this text won't become outdated; I've tried to keep the code fairly self-documenting
    to avoid stale comments.

    First, it depends on dextercd's excellent NoitaDearImGui mod that brings the Dear ImGui library
    to Noita.
    This was a must. It has the downside that the mod and its requirements can't be placed on the
    Steam Workshop, and that it requires "unsafe" mods to be enabled in Noita.
    However, the advantages were just too great to ignore. I went from 6 ms(!) to render my UI down to a small
    enough number that I can't tell. Maybe about 0.1 ms most of the time, with 10 rows showing.
    6 ms is enough to bring you from hovering around 60 fps down to 44 fps while the GUI is shown, and
    with 20-25 rows shown the hit was far larger, going down to 20 fps and below.
    In addition, we get a far nicer design, easy settings, column reordering, column resizing and so much more.

    The mod is set up in OnPlayerSpawned (in this file) by adding a LuaComponent that calls
    damage_received() (in files/damage.lua) whenever the player takes damage.

    damage_received() stores the damage in a List (technically a double-ended queue), and then
    serializes it to a plain-text string and stores it with GlobalsSetValue.
    That is necessary because scripts can't easily communicate with one another; they seem to run
    in different Lua contexts, so they can't share larger amounts of data easily.
    It also stores the ID of the latest hit that it has written to a separate global.

    OnWorldPostUpdate then reads the ID of the latest hit and compares it to the highest ID it has seen.
    If the latest ID is higher, it calls update_gui_data() which transforms some of the values into GUI-friendly
    strings. It then sets a global telling damage.lua which IDs it has seen, so that damage.lua can remove
    those hits from the List on the next hit, so that they won't be serialized/deserialized and transferred again.

    Finally, draw_gui() uses the transformed GUI data and draws it to the screen, if display_gui is set.
]]

-- The processed version of the damage data, i.e. formatted strings for the GUI
local gui_data = List.new()

-- State that can't be directly affected by the player
local initial_clear_completed = false
local last_imgui_warning_time = -3
local player_spawn_time = 0
local reset_window_settings = false -- window size/position will be cleared (once) if true
local display_gui_after_wand_pickup = nil
local display_gui = false

-- Initialized in load_settings, called on mod initialization.
-- Read from and written to using get_setting and set_setting, respectively.
local _settings = {}

local max_rows_allowed = 60 -- Player has the choice of showing 1 to this many rows
local _default_settings = {
    -- Behavior
    auto_size_columns = true,
    show_log_on_load = false,
    show_on_pause_screen = true,
    auto_show_hide_on_pause = false,
    activation_ctrl = true,
    activation_shift = false,
    activation_alt = false,
    activation_key = 17, -- 17th in the array, which is Q
    -- Appearance
    font = 1,
    max_rows_to_show = 15,
    show_grid_lines = true,
    alternate_row_colors = false,
    foreground_opacity = 0.7,
    background_opacity = 0.3,
    -- Advanced
    ignore_mouse_input = false,
    -- Pseudo-settings (not shown in UI)
    show_help_window = true, -- Shown on first start only; this is set to false when the window is closed
    reset_settings_now = false, -- Set in Noita's Mod Settings menu to clear everything. Auto-reset to false afterwards.
    force_show_on_load = true, -- Used until the user has seen the settings OR used the activation hotkey
}

local function reset_settings()
    for key, default_value in pairs(_default_settings) do
        ModSettingRemove("damagelog." .. key)
        _settings[key] = default_value
    end

    reset_window_settings = true
    log("Mod settings cleared!")
end

local function load_settings()
    if ModSettingGet("damagelog.reset_settings_now") then
        reset_settings()
        return
    end

    for key, default_value in pairs(_default_settings) do
        local stored_value = ModSettingGet("damagelog." .. key)
        _settings[key] = choice(stored_value ~= nil, stored_value, default_value)
    end
end

local function get_setting(key)
    local value = _settings[key]
    if value == nil then
        error("Invalid setting key: " .. key)
    end

    return value
end

local function set_setting(key, value)
    if _default_settings[key] == nil then
        error("Invalid setting key: " .. key)
    end
    _settings[key] = value
    ModSettingSet("damagelog." .. key, value)
end

-- A bit overly involved, but this way we can get automatic calls to get_setting and set_setting
-- with only specifying the setting key (once), which would be much messier if we needed to
-- check the imgui.* return value for every setting individually.
local function create_widget(setting_name, widget_creator, on_change_callback)
    return function(label, ...)
        local did_change, new_value = widget_creator(label, get_setting(setting_name), ...)
        if did_change then
            set_setting(setting_name, new_value)
            if on_change_callback ~= nil then
                on_change_callback(setting_name, new_value)
            end
        end
    end
end

local fonts = {
    {"Noita Pixel", imgui.GetNoitaFont()},
    {"Noita Pixel 1.4x", imgui.GetNoitaFont1_4x()},
    {"Noita Pixel 1.8x", imgui.GetNoitaFont1_8x()},
    {"ImGui (Proggy Clean)", imgui.GetImGuiFont()},
    {"Source Code Pro", imgui.GetMonospaceFont()},
}

function format_time(time, lower_accuracy)
    local current_time = GameGetRealWorldTimeSinceStarted()
    local diff = math.floor(current_time - time)
    if diff < 0 then
        return "?"
    elseif (not lower_accuracy and diff < 1) or (lower_accuracy and diff < 3) then
        -- lower_accuracy is used by e.g. toxic sludge stains, so that the time
        -- doesn't keep jumping between now -> 1s -> 2s -> now -> ... while stained
        return "now"
    elseif diff < 60 then
        return string.format("%.0fs", diff)
    elseif diff < 300 then
        local min, sec = math.floor(diff / 60), math.floor(diff % 60)
        return string.format("%.0fm %.0fs", min, sec)
    elseif diff < 7200 then
        -- Don't show seconds since it's mostly annoying at this point
        return string.format("%.0fm", diff / 60)
    else
        local hr, min = math.floor(diff / 3600), math.floor((diff % 3600) / 60)
        return string.format("%.0fh %.0fm", hr, min)
    end
end

-- Uses a simple human-readable format for only partially insane numbers (millions, billions).
-- Reverts to scientific notation shorthand (e.g. 1.23e14) for the truly absurd ones.
 function format_number(n)
    if n < 1000000 then -- below 1 million, show as plain digits e.g. 987654
        -- Format, and prevent string.format from rounding to 0
        local formatted = string.format("%.0f", n)
        if formatted == "0" and n > 0 then
            formatted = "<1"
        end
        return formatted
    elseif n < 1000000000 then
        -- Below 1 billion, show as e.g. 123.4M
        return string.format("%.4gM", n/1000000)
    elseif n < 1000000000000 then
        -- Below 1 trillion, show as e.g. 123.4B
        return string.format("%.4gB", n/1000000000)
    else
        -- Format to exponent notation, and convert e.g. 1.3e+007 to 1.3e7
        return (string.format("%.4g", n):gsub("e%+0*", "e"))
    end
end

local function should_pool_damage(source, type)
    if List.isempty(gui_data) then return false end
    local prev = List.peekright(gui_data)

    if prev.source ~= source or prev.type ~= type then
        return false
    end

    local frame_diff = GameGetFrameNum() - prev.frame
    return frame_diff < 120
end

function draw_help_window()
    if not imgui or GameIsInventoryOpen() then return end

    local spacing_size = 0.5 -- * FontSize
    local font = get_setting("font")
    imgui.PushFont(fonts[font][2])

    imgui.SetNextWindowPos(220, 330, imgui.Cond.Once)

    local window_flags = imgui.WindowFlags.AlwaysAutoResize
    window_shown, should_show = imgui.Begin("Damage log help", get_setting("show_help_window"), window_flags)

    -- This method is only called when show_help_window is true, so if this now returned FALSE,
    -- that means the user just closed the window and Begin returned _, false.
    if not should_show then
        imgui.PopFont()
        imgui.End() -- Hmm, why is this needed here, but not in draw_gui()?
        set_setting("show_help_window", false)
        return
    end

    if not window_shown then
        -- Window is collapsed
        imgui.PopFont()
        return
    end

    imgui.Text("This window will be only be shown once!")
    imgui.Text("However, it can be accessed from the settings window (see below).")

    imgui.Dummy(0, imgui.GetFontSize())

    imgui.Text("To toggle the damage log: Ctrl+Q by default, can be changed in the settings")
    imgui.Text("To access settings: right-click any *non-header* row in the window")
    imgui.Text("To hide/unhide columns: right-click any column header")
    imgui.Text("To rearrange columns: left-click and drag the column header")
    imgui.Text("To manually resize: disable auto-sizing in settings, then click+drag the column divider")

    imgui.Dummy(0, spacing_size * imgui.GetFontSize())

    imgui.Text([[Note that the "location" column is hidden by default.]])
    imgui.Text([[It shows in which biome the damage was taken.]])

    imgui.Dummy(0, spacing_size * imgui.GetFontSize())

    if imgui.Button("Close") then
        set_setting("show_help_window", false)
    end

    imgui.End()
    imgui.PopFont()
end

function draw_gui()
    if not display_gui or not imgui or GameIsInventoryOpen() then
        return
    end

    -- These are used multiple times below
    local auto_size_columns = get_setting("auto_size_columns")
    local font = get_setting("font")
    local max_rows_to_show = get_setting("max_rows_to_show")

    -- These are pushed initially, then popped to not affect the popup windows.
    local function push_main_window_vars()
        local foreground_opacity = get_setting("foreground_opacity")
        local accent_main = {0.58, 0.50, 0.39, foreground_opacity}
        local accent_light = {0.70, 0.62, 0.51, foreground_opacity}

        imgui.PushStyleColor(imgui.Col.TitleBg, unpack(accent_main))

        if get_setting("ignore_mouse_input") then
            -- Window is still highlighted when clicked, which is ugly, so hide that
            imgui.PushStyleColor(imgui.Col.TitleBgActive, unpack(accent_main))
        else
            imgui.PushStyleColor(imgui.Col.TitleBgActive, unpack(accent_light))
        end

        imgui.PushStyleColor(imgui.Col.Border, unpack(accent_main))
        imgui.PushStyleColor(imgui.Col.Text, 1, 1, 1, foreground_opacity)

        imgui.PushStyleColor(imgui.Col.TableBorderLight, 0.4, 0.4, 0.4, foreground_opacity)
        imgui.PushStyleColor(imgui.Col.TableBorderStrong, 0.55, 0.55, 0.55, foreground_opacity)

        imgui.PushStyleVar(imgui.StyleVar.WindowPadding, 0, 0)
    end

    local function pop_main_window_vars()
        imgui.PopStyleVar()
        imgui.PopStyleColor(6)
    end

    -- Used while drawing the settings
    local spacing_size = 0.5 -- * FontSize

    push_main_window_vars()
    imgui.PushFont(fonts[font][2])
    imgui.SetNextWindowBgAlpha(get_setting("background_opacity"))

    if reset_window_settings then
        imgui.SetNextWindowPos(120, 200, imgui.Cond.Always) -- Technically once anyway
        reset_window_settings = false
    end

    local window_flags = imgui.WindowFlags.AlwaysAutoResize
    if get_setting("ignore_mouse_input") then
        window_flags = bit.bor(window_flags, imgui.WindowFlags.NoMouseInputs)
    end

    window_shown, display_gui = imgui.Begin("Damage log", display_gui, window_flags)

    if not window_shown then
        -- Window is collapsed
        pop_main_window_vars()
        imgui.PopFont()
        return
    end

    if font == 2 or font == 3 then
        -- These larger fonts need more padding to look right
        imgui.PushStyleVar(imgui.StyleVar.CellPadding, 10, 6)
    else
        imgui.PushStyleVar(imgui.StyleVar.CellPadding, 7, 3)
    end

    local table_flags = bit.bor(
        imgui.TableFlags.Reorderable,
        imgui.TableFlags.Hideable,
        imgui.TableFlags.BordersOuter,
        choice(not auto_size_columns, imgui.TableFlags.Resizable, 0),
        choice(get_setting("alternate_row_colors"), imgui.TableFlags.RowBg, 0),
        choice(get_setting("show_grid_lines"), imgui.TableFlags.BordersInner, 0)
    )

    imgui.BeginTable("Damage", 6, table_flags)

    -- Column setup + headers
    if font == 2 or font == 3 then
        imgui.PushStyleVar(imgui.StyleVar.CellPadding, 10, 8)
    end

    imgui.PushStyleColor(imgui.Col.TableHeaderBg, 0.45, 0.45, 0.45, get_setting("foreground_opacity"))
    imgui.TableSetupColumn("Location", imgui.TableColumnFlags.DefaultHide)
    imgui.TableSetupColumn("Source")
    imgui.TableSetupColumn("Type")
    imgui.TableSetupColumn("Damage")
    imgui.TableSetupColumn("HP")
    imgui.TableSetupColumn("Time")
    imgui.TableHeadersRow()
    imgui.PopStyleColor()

    if font == 2 or font == 3 then
        imgui.PopStyleVar()
    end

    -- Show "Hitless" if there are no hits registered yet
    -- The for loop won't run in this case, so we don't need to move all of that
    -- inside an else clause.
    if List.length(gui_data) == 0 then
        imgui.TableNextRow()


        imgui.TableNextColumn()
        imgui.Text(" ")
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
        imgui.Text(gui_data[row].location)

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

        -- So this is unfortunately very hacky.
        -- To keep the GUI time updated in most cases while also not jumping back between
        -- now -> 1s -> 2s -> now -> ... for some pooled damage, we need to use an exception
        -- for such damage. There may be more exceptions than these that should be added.
        -- TODO: ensure this works with non-English languages used in Noita
        local s = gui_data[row].source
        local lower_accuracy = s == "Toxic sludge" or s == "Poison"
        imgui.TableNextColumn()
        imgui.Text(format_time(gui_data[row].time, lower_accuracy))
    end

    -- Add popup to right-clicking on any of the columns (except the header)
    local is_any_column_hovered = false
    for column = 0, 4 do
        if bit.band(imgui.TableGetColumnFlags(column), imgui.TableColumnFlags.IsHovered) ~= 0 then
            -- This is where I learned that 0 evaluates to true in Lua!
            is_any_column_hovered = true
            break
        end
    end

    pop_main_window_vars()
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, 8, 8)

    imgui.PushID("123")
    if is_any_column_hovered and not imgui.IsAnyItemHovered() and imgui.IsMouseReleased(1) then
        imgui.OpenPopup("SettingsPopup")
    end

    if imgui.BeginPopup("SettingsPopup") then
        imgui.Text("Settings are applied and saved immediately.")

        set_setting("force_show_on_load", false)

        ---------------- Start of settings ----------------

        imgui.SeparatorText("Behavior")

        -- These follow a different pattern than the others, so create_widget isn't used
        if imgui.RadioButton("Auto-size columns to fit", auto_size_columns) then
            set_setting("auto_size_columns", true)
        end
        if imgui.RadioButton("Manual sizing (click divider + drag).", not auto_size_columns) then
            set_setting("auto_size_columns", false)
        end

        local show_log_on_load_creator = create_widget("show_log_on_load", imgui.Checkbox)
        show_log_on_load_creator("Open damage log when Noita starts")

        local show_on_pause_screen_creator = create_widget("show_on_pause_screen", imgui.Checkbox,
            function(setting, new_value)
                if not new_value then
                    set_setting("auto_show_hide_on_pause", false)
                end
            end
        )
        show_on_pause_screen_creator("Show log on pause screen")

        local open_on_pause_creator = create_widget("auto_show_hide_on_pause", imgui.Checkbox,
            function(setting, new_value)
                if new_value then
                    set_setting("show_on_pause_screen", true)
                end
            end
        )
        open_on_pause_creator("Open/close damage log on pause/unpause")

        imgui.Dummy(0, spacing_size * imgui.GetFontSize())

        imgui.Text("Activation hotkey")
        imgui.SameLine()
        local activation_ctrl_creator = create_widget("activation_ctrl", imgui.Checkbox)
        activation_ctrl_creator("Ctrl")
        imgui.SameLine()
        local activation_alt_creator = create_widget("activation_alt", imgui.Checkbox)
        activation_alt_creator("Alt")
        imgui.SameLine()
        local activation_shift_creator = create_widget("activation_shift", imgui.Checkbox)
        activation_shift_creator("Shift")
        imgui.SameLine()

        -- These are in the same order as in data/scripts/debug/keycodes.lua, which is also why some other
        -- potentially useful keys are not listed
        local allowed_keys = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R',
            'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'}

        imgui.PushItemWidth(imgui.GetFontSize() * 3)
        local key_creator = create_widget("activation_key", imgui.Combo)
        key_creator("##Key", allowed_keys)
        imgui.PopItemWidth()

        imgui.SeparatorText("Appearance")

        local font_creator = create_widget("font", imgui.Combo)
        font_creator("Font", {
            "Noita Pixel",
            "Noita Pixel 1.4x",
            "Noita Pixel 1.8x",
            "ImGui (Proggy Clean)",
            "Source Code Pro"
        })

        local max_rows_to_show_creator = create_widget("max_rows_to_show", imgui.SliderInt)
        max_rows_to_show_creator("Max rows to show", 1, max_rows_allowed)

        local show_grid_lines_creator = create_widget("show_grid_lines", imgui.Checkbox)
        show_grid_lines_creator("Show grid lines")

        local alternate_row_colors_creator = create_widget("alternate_row_colors", imgui.Checkbox)
        alternate_row_colors_creator("Alternate row colors")

        local foreground_opacity_creator = create_widget("foreground_opacity", imgui.SliderFloat)
        foreground_opacity_creator("Foreground opacity (text etc)", 0.1, 1.0)

        local background_opacity_creator = create_widget("background_opacity", imgui.SliderFloat)
        background_opacity_creator("Background opacity", 0.0, 1.0)

        imgui.SeparatorText("Advanced")

        imgui.Text([[Mouse click-through can be enabled in Noita's "Mod Settings" menu.]])
        imgui.Text([[When enabled, accessing this window is impossible,]])
        imgui.Text([[so it must be disabled again to change other settings.]])
        imgui.Dummy(0, spacing_size * imgui.GetFontSize())

        ---------------- End of settings ----------------

        if imgui.Button("Close") then
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button("Restore default settings") then
            imgui.OpenPopup("ConfirmRestorePopup")
        end
        imgui.SameLine()
        if imgui.Button("Help") then
            set_setting("show_help_window", true)
        end

        if imgui.BeginPopup("ConfirmRestorePopup") then
            imgui.Text("Are you sure you want to restore the default settings?")

            if imgui.Button("Yes, restore defaults") then
                reset_settings()
                imgui.CloseCurrentPopup()
            end
            imgui.SameLine()
            if imgui.Button("No, abort") then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup() -- ConfirmRestorePopup
        end

        imgui.EndPopup() -- SettingsPopup
    end
    imgui.PopID()
    imgui.PopStyleVar() -- WindowPadding for SettingsPopup

    imgui.EndTable()
    imgui.PopStyleVar() -- CellPadding for the table
    imgui.End() -- Damage log window
    imgui.PopFont()
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

        local location
        if damage_entry.location:sub(1, 1) == '$' then
            location = GameTextGet(damage_entry.location)
        else
            location = damage_entry.location
        end

        source = initialupper(source)
        type = initialupper(type)
        location = initialupper(location)

        -- Pool damage from fast sources (like fire, once per frame = 60 times per second),
        -- if the last damage entry was from the same source *AND* it was recent.
        -- Note that this uses popright to remove the previous row entirely.
        local pooled_damage = 0
        if damage_entry.is_poolable and should_pool_damage(source, type) then
            pooled_damage = List.popright(gui_data).raw_damage
        end

        List.pushright(gui_data, {
            source = source,
            type = type,
            damage = { damage_entry.damage < 0, format_number(damage_entry.damage + pooled_damage) },
            raw_damage = damage_entry.damage + pooled_damage,
            hp = format_number(damage_entry.hp),
            time = math.floor(damage_entry.time), -- Formatted on display. floor() to make them all update in sync
            frame = damage_entry.frame,
            location = location,
            id = damage_entry.id
        })
    end

    -- Clean up excessive entries
    while List.length(gui_data) > max_rows_allowed do
        List.popleft(gui_data)
    end
end

local function activation_hotkey_was_just_pressed()
    -- NOTE: This requires Noita beta OR a newer build.
    -- As of this writing (2024-04-08) the main branch was updated to have these methods *today*.
    -- If modifier keys are used, this requires the non-modifier key to be pressed last -- as you're used to.

    local use_ctrl = get_setting("activation_ctrl")
    local use_shift = get_setting("activation_shift")
    local use_alt = get_setting("activation_alt")

    -- So we have the activation_key setting, which is 1 for 'A', ... 26 for 'Z', 27 for '1', ... ending in '9', '0'
    -- We need to convert that to the index used by Noita, which is 4 for 'A', and so on, in the same order.
    local key = get_setting("activation_key") + Key_a - 1

    return
        (not use_ctrl or InputIsKeyDown(Key_LCTRL) or InputIsKeyDown(Key_RCTRL)) and
        (not use_shift or InputIsKeyDown(Key_LSHIFT) or InputIsKeyDown(Key_RSHIFT)) and
        (not use_alt or InputIsKeyDown(Key_LALT) or InputIsKeyDown(Key_RALT)) and
        InputIsKeyJustDown(key)
end

function handle_input_and_gui()
    if not imgui then
        -- Not sure how else to handle this. Spam warnings often if imgui is not available, since the mod will be useless.
        local current_time = GameGetRealWorldTimeSinceStarted()
        if current_time - last_imgui_warning_time > 5 then
            GamePrint("damagelog: ImGui not available! Ensure NoitaDearImGui mod is installed, active, and ABOVE this mod in the mod list!")
            last_imgui_warning_time = current_time
        end
    end

    if activation_hotkey_was_just_pressed() then
        display_gui = not display_gui
        if get_setting("force_show_on_load") then
            set_setting("force_show_on_load", false)
        end
    end

    local highest_id_read = 0
    if not List.isempty(gui_data) then
        highest_id_read = List.peekright(gui_data).id
    end

    local highest_id_written = tonumber(GlobalsGetValue("damagelog_highest_id_written", "0"))
    if highest_id_written > highest_id_read then
        update_gui_data()
    end

    draw_gui()

    if get_setting("show_help_window") then
        draw_help_window()
    end
end

function OnModInit()
    load_settings()

    -- Show the GUI until the user has seen the settings, to make sure they know how to open the log window
    -- Also reset once they've toggled the window with the activation hotkey.
    display_gui = get_setting("show_log_on_load") or get_setting("force_show_on_load")
end

function OnPausedChanged(is_paused, is_inventory_pause)
    if is_inventory_pause or display_gui_after_wand_pickup ~= nil then
        if is_paused then
            -- Picking up a wand. Always hide the GUI if it's shown, but show it again afterwards
            -- if it was visible to begin with
            display_gui_after_wand_pickup = display_gui
            display_gui = false
        else
            display_gui = display_gui_after_wand_pickup
            display_gui_after_wand_pickup = nil
        end
    elseif is_paused then
        -- "Standard" pause, i.e. the escape menu
        if get_setting("auto_show_hide_on_pause") then
            display_gui = true
        end
    else
        -- Return from the escape menu
        load_settings()
        if get_setting("auto_show_hide_on_pause") then
            display_gui = false
        end
    end
end

function OnPausePreUpdate()
    if get_setting("show_on_pause_screen") then
        handle_input_and_gui()
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

    handle_input_and_gui()
end

-- Called by Noita when the player spawns. Must have this name.
function OnPlayerSpawned(player_entity)
    if player_entity == nil then
        log("OnPlayerSpawned called, but player_entity not found!")
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