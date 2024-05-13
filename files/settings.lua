-- Initialized in load_settings, called on mod initialization.
-- Read from and written to using get_setting and set_setting, respectively.
local _settings = {}

max_rows_allowed = 60 -- Player has the choice of showing 1 to this many rows
local _default_settings = {
    -- Behavior
    auto_size_columns = true,
    combine_similar_hits = true,
    show_log_on_load = false,
    show_on_pause_screen = false,
    auto_show_hide_on_pause = false,
    show_total_damage = false,
    log_healing = false,
    activation_ctrl = true,
    activation_shift = false,
    activation_alt = false,
    activation_key = 17, -- 17th in the array, which is Q
    -- Appearance
    highlight_combined_asterisk = true,
    highlight_combined_red = false,
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
    reset_window_position_now = false, -- Set by reset_settings when the above is true
    force_show_on_load = true, -- Used until the user has seen the settings OR used the activation hotkey
}

function reset_settings()
    for key, default_value in pairs(_default_settings) do
        ModSettingRemove("damagelog." .. key)
        _settings[key] = default_value
    end

    _settings.reset_window_position_now = true
    log("Mod settings cleared!")
end

function load_settings()
    if ModSettingGet("damagelog.reset_settings_now") then
        reset_settings()
        return
    end

    for key, default_value in pairs(_default_settings) do
        local stored_value = ModSettingGet("damagelog." .. key)
        _settings[key] = choice(stored_value ~= nil, stored_value, default_value)
    end
end

function get_setting(key)
    local value = _settings[key]
    if value == nil then
        error("Invalid setting key: " .. key)
    end

    return value
end

function set_setting(key, value)
    if _default_settings[key] == nil then
        error("Invalid setting key: " .. key)
    end
    _settings[key] = value
    ModSettingSet("damagelog." .. key, value)
end