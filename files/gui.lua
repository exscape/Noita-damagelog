-- This can't be a local as init.lua checks for it
imgui = nil
if load_imgui ~= nil then
    -- Prevent Lua error when the mod isn't available
    -- Actual error reporting to the user is in the callbacks far below
    imgui = load_imgui({version="1.17.0", mod="damagelog"})
end

dofile_once('data/scripts/debug/keycodes.lua')

local fonts
if imgui then
    fonts = {
        {"Noita Pixel", imgui.GetNoitaFont()},
        {"Noita Pixel 1.4x", imgui.GetNoitaFont1_4x()},
        {"Noita Pixel 1.8x", imgui.GetNoitaFont1_8x()},
        {"ImGui (Proggy Clean)", imgui.GetImGuiFont()},
        {"Source Code Pro", imgui.GetMonospaceFont()},
    }
end

local gui_state = {}

function init_gui()
    -- The processed version of the damage data, i.e. formatted strings for the GUI
    gui_state.data = List.new()

    -- Show the GUI until the user has seen the settings, to make sure they know how to open the log window
    -- Also reset once they've toggled the window with the activation hotkey.
    gui_state.display_gui = get_setting("show_log_on_load") or get_setting("force_show_on_load")

    -- There doesn't seem to be a GameIsPaused or similar, so let's make one
    gui_state.is_paused = false

    -- Actually set in init.lua, but having a non-nil value prior to that saves us a bunch of checks
    gui_state.player_spawn_time = 0

    return gui_state
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

-- Associates a tooltip to the *last* created widget, not the upcoming one!
local function create_tooltip(s)
    if imgui.IsItemHovered(imgui.HoveredFlags.ForTooltip) then
        imgui.SetTooltip(s)
    end
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
    imgui.Text("To move the window: click and drag the titlebar")
    imgui.Text("To access settings: right-click any *non-header* row in the window")
    imgui.Text("To hide/unhide columns: right-click any column header")
    imgui.Text("To rearrange columns: left-click and drag the column header")
    imgui.Text("To manually resize: disable auto-sizing in settings, then click+drag the column divider")

    imgui.Dummy(0, spacing_size * imgui.GetFontSize())

    imgui.Text([[Note that the "Location" and "Max HP" columns are hidden by default.]])

    imgui.Dummy(0, spacing_size * imgui.GetFontSize())

    if imgui.Button("Close") then
        set_setting("show_help_window", false)
    end

    imgui.End()
    imgui.PopFont()
end

function draw_gui()
    if not gui_state.display_gui or not imgui or GameIsInventoryOpen() then
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

    if get_setting("reset_window_position_now") then
        imgui.SetNextWindowPos(120, 200, imgui.Cond.Always) -- Technically once anyway
        set_setting("reset_window_position_now", false)
    end

    local window_flags = imgui.WindowFlags.AlwaysAutoResize
    if get_setting("ignore_mouse_input") and
       not gui_state.is_paused and
       not (InputIsKeyDown(Key_LCTRL) and InputIsKeyDown(Key_LALT)) then
        window_flags = bit.bor(window_flags, imgui.WindowFlags.NoMouseInputs)
    end

    local total_damage_string = ""
    if get_setting("show_total_damage") then
        total_damage_string = choice(gui_state.data.total_damage ~= nil, gui_state.data.total_damage, " (hitless)")
    end

    local window_title_and_id = "Damage log" .. total_damage_string .. "###damagelog"

    window_shown, gui_state.display_gui = imgui.Begin(window_title_and_id, gui_state.display_gui, window_flags)

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

    local num_columns = 7
    imgui.BeginTable("Damage", num_columns, table_flags)

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
    imgui.TableSetupColumn("Max HP", imgui.TableColumnFlags.DefaultHide)
    imgui.TableSetupColumn("Time")
    imgui.TableHeadersRow()
    imgui.PopStyleColor()

    if font == 2 or font == 3 then
        imgui.PopStyleVar()
    end

    -- Show "Hitless" if there are no hits registered yet
    -- The for loop won't run in this case, so we don't need to move all of that
    -- inside an else clause.
    if List.length(gui_state.data) == 0 then
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
        imgui.Text(" ")
        imgui.TableNextColumn()
        imgui.Text(format_time(gui_state.player_spawn_time))
    end

    local first_index
    if List.length(gui_state.data) <= max_rows_to_show then
        first_index = gui_state.data.first
    else
        first_index = gui_state.data.last - max_rows_to_show + 1
    end

    for row = first_index, gui_state.data.last do
        imgui.TableNextRow()
        local row_data = gui_state.data[row]

        imgui.TableNextColumn()
        imgui.Text(row_data.location)

        imgui.TableNextColumn()
        imgui.Text(row_data.source)

        imgui.TableNextColumn()
        imgui.Text(row_data.type)

        imgui.TableNextColumn()

        local num_hits = #row_data.hits
        local damage_text = row_data.damage_text
        if num_hits > 1 and get_setting("highlight_combined_asterisk") then
            damage_text = damage_text .. "*"
        end
        if row_data.total_damage < 0 then
            -- Healing, show in green
            imgui.TextColored(0.25, 0.8, 0.25, 1.0, damage_text)
        elseif num_hits > 1 and get_setting("highlight_combined_red") then
            -- Combined hits w/ highlight
            imgui.TextColored(0.8, 0.25, 0.25, 1.0, damage_text)
        else
            -- Standard hit
            imgui.Text(damage_text)
        end

        if row_data.damage_tooltip then
            -- Used when there are multiple hits
            create_tooltip(row_data.damage_tooltip)
        end

        imgui.TableNextColumn()
        imgui.Text(row_data.hp)

        imgui.TableNextColumn()
        imgui.Text(row_data.max_hp)

        -- So this is unfortunately very hacky.
        -- To keep the GUI time updated in most cases while also not jumping back between
        -- now -> 1s -> 2s -> now -> ... for some pooled damage, we need to use an exception
        -- for such damage. There may be more exceptions than these that should be added.
        -- TODO: ensure this works with non-English languages used in Noita
        local lower_accuracy = row_data.source == "Toxic sludge" or row_data.source == "Poison"
        imgui.TableNextColumn()
        imgui.Text(format_time(row_data.time, lower_accuracy))
    end

    -- Add popup to right-clicking on any of the columns (except the header)
    local is_any_column_hovered = false
    for column = 0, num_columns - 1 do
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
        if imgui.RadioButton("Manual sizing (click divider + drag)", not auto_size_columns) then
            set_setting("auto_size_columns", false)
        end
        create_tooltip("Column sizes will be remembered when manual sizing is enabled.")

        local show_log_on_load_creator = create_widget("show_log_on_load", imgui.Checkbox)
        show_log_on_load_creator("Open damage log when Noita starts")
        create_tooltip("Shows the damage log window whenever you start or continue a run.")

        local show_on_pause_screen_creator = create_widget("show_on_pause_screen", imgui.Checkbox,
            function(setting, new_value)
                if not new_value then
                    set_setting("auto_show_hide_on_pause", false)
                end
            end
        )
        show_on_pause_screen_creator("Show log on pause screen")
        create_tooltip("When enabled, the log (and settings/help) will also show up when the game is paused.\nIt will unfortunately also show up over settings, the replay editor etc, which can't be prevented.")

        local open_on_pause_creator = create_widget("auto_show_hide_on_pause", imgui.Checkbox,
            function(setting, new_value)
                if new_value then
                    set_setting("show_on_pause_screen", true)
                end
            end
        )
        open_on_pause_creator("Open/close damage log on pause/unpause")
        create_tooltip("Requires 'Show log on pause screen'.\nHandy way to check the log with no risk of getting killed!\nHowever, the log will also show over settings, the replay editor etc, which can't be prevented.")

        local show_total_damage_creator = create_widget("show_total_damage", imgui.Checkbox)
        show_total_damage_creator("Show total damage taken in the window title")

        local log_healing_creator = create_widget("log_healing", imgui.Checkbox)
        log_healing_creator("Log healing (see tooltip)")
        create_tooltip("Logs healing from negative damage hits like Healing Bolt only.\n" ..
                       "Healing from Deadly Heal, Circle of Vigour, full heal pickups etc.\n" ..
                       "won't be shown, as Noita doesn't notify the mod of such healing.")

        imgui.Dummy(0, spacing_size * imgui.GetFontSize())

        local combine_hits_creator = create_widget("combine_similar_hits", imgui.Checkbox)
        combine_hits_creator("Combine similar, near-simultaneous hits into a single row")
        create_tooltip("Show e.g. the 4 hits of a Hiisi shotgunner as one row of 28, instead of 4 rows of 7.\n" ..
                       "Mouse over the damage text to show the individual hits.\n" ..
                       "Some rounding issues can occur, e.g. 2 x 6.4 damage shows as \"2x6\" but the total rounds to 13.")

        imgui.Indent()

        local combine_hits_highlight_asterisk = create_widget("highlight_combined_asterisk", imgui.Checkbox)
        combine_hits_highlight_asterisk("Highlight combined hits with an asterisk")

        local combine_hits_highlight_red = create_widget("highlight_combined_red", imgui.Checkbox)
        combine_hits_highlight_red("Highlight combined hits in red")

        imgui.Unindent()

        imgui.Dummy(0, spacing_size * imgui.GetFontSize())

        local activation_tooltip = "Any combination of Ctrl/Alt/Shift is allowed, including using none of them."
        imgui.Text("Activation hotkey")
        create_tooltip(activation_tooltip)
        imgui.SameLine()
        local activation_ctrl_creator = create_widget("activation_ctrl", imgui.Checkbox)
        activation_ctrl_creator("Ctrl")
        create_tooltip(activation_tooltip)
        imgui.SameLine()
        local activation_alt_creator = create_widget("activation_alt", imgui.Checkbox)
        activation_alt_creator("Alt")
        create_tooltip(activation_tooltip)
        imgui.SameLine()
        local activation_shift_creator = create_widget("activation_shift", imgui.Checkbox)
        activation_shift_creator("Shift")
        create_tooltip(activation_tooltip)
        imgui.SameLine()

        -- These are in the same order as in data/scripts/debug/keycodes.lua, which is also why some other
        -- potentially useful keys are not listed
        local allowed_keys = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R',
            'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'}

        imgui.PushItemWidth(imgui.GetFontSize() * 3)
        local key_creator = create_widget("activation_key", imgui.Combo)
        key_creator("##Key", allowed_keys)
        create_tooltip(activation_tooltip)
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
        create_tooltip("The log will resize as you take damage, up to this number of rows.")

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
        imgui.Text([[When the left ctrl and alt keys are held, mouse input is always accepted,]])
        imgui.Text([[even when the click-through setting is enabled.]])
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
