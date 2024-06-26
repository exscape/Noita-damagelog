dofile("data/scripts/lib/mod_settings.lua") -- see this file for documentation on some of the features.

local mod_id = "damagelog"
mod_settings_version = 1

function ui_show_text(mod_id, gui, in_main_menu, im_id, setting)
    GuiText(gui, mod_setting_group_x_offset, 0, setting.ui_name .. ":\n" .. setting.ui_description)
end

mod_settings =
{
    {
        category_id = "preferences",
        ui_name = "Preferences",
        ui_description = "Preferences",
        settings = {
            {
                id = "ignore_mouse_input",
                ui_name = "Click-through / ignore all(!) mouse input (unless paused)",
                ui_description = "ALL mouse input is ignored and sent to Noita instead,\n" ..
                    "including right-clicks, window moves, etc.\n" ..
                    "Nice to have if you want the window always visible,\n" ..
                    "to avoid accidental clicks when attacking.\n" ..
                    "Hold left Ctrl + left Alt to temporarily allow mouse input!",
                value_default = false,
                scope = MOD_SETTING_SCOPE_RUNTIME,
            },
            {
                id = "reset_settings_now",
                ui_name = "Restore default mod settings (once)",
                ui_description = "Emergency fix in case you can't access the damage log in-game for any reason.",
                value_default = false,
                scope = MOD_SETTING_SCOPE_RUNTIME,
            },
            {
                ui_fn = mod_setting_vertical_spacing,
                not_setting = true,
            },
            {
                ui_fn = ui_show_text,
                ui_name = "Please note",
                ui_description = "    Other settings for this mod are accessed by right-clicking\n" ..
                                 "    in any non-header row in the log in-game.\n" ..
                                 "    If you can't access the log for whatever reason, restore the\n" ..
                                 "    settings above and go back into the game, and it should show up.",
                not_setting = true,
            },
        },
    },
}

function ModSettingsUpdate(init_scope)
    mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
