dofile_once('data/scripts/debug/keycodes.lua')

dofile_once("mods/damagelog/files/utils.lua")
dofile_once("mods/damagelog/files/list.lua")
dofile_once("mods/damagelog/files/settings.lua")
dofile_once("mods/damagelog/files/gui.lua")

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

    handle_input_and_gui (via OnWorldPostUpdate) then reads the ID of the latest hit and compares it to the highest ID it has seen.
    If the latest ID is higher, it calls update_gui_data() which transforms some of the values into GUI-friendly
    strings. It then sets a global telling damage.lua which IDs it has seen, so that damage.lua can remove
    those hits from the List on the next hit, so that they won't be serialized/deserialized and transferred again.

    Finally, draw_gui() uses the transformed GUI data and draws it to the screen, if gui_state.display_gui is set.

    The script uses two different Lua contexts: one for damage.lua, and one for init.lua + gui.lua.
    This is because how Noita works with the LuaComponent scripts, and is something I'd really prefer to not do.
    Because of the separate contexts, most data (even technically damage data) is stored outside of damage.lua;
    otherwise, we would need to pass large amounts of data back and forth every time we get damaged (or even every frame).
]]

-- Initialized in OnModInit -- should be nil, but to prevent incorrect warnings/unnecessary nil checks, let's initialize it here too
local gui_state = {}

-- State that can't be directly affected by the player
local initial_setup_completed = false
local last_imgui_warning_time = -3
local display_gui_after_wand_pickup = nil

-- Used to check if damage should be added together and shown as one number,
-- such as for fire (60 times/second!), toxic sludge, poison and some others.
-- Also used for combining near-simultaneous hits (which preserves individual hit info).
local function fetch_pooling_entry(source, type, max_frame_diff)
    if List.isempty(gui_state.data) then return nil end

    -- Look for a matching entry from the last few rows.
    -- Preferably, we would only pool to the very last row, but it causes issues in several cases.
    -- For example: being hit by enemies while on fire (causes many fire rows, one extra per hit), or
    -- being hit by multiple enemies quickly, or getting hit by many damage types quickly (such as from omega discs).
    -- All of the above cause log spam if we only pool to the last row.
    --
    -- Note to self: keep in mind this checks 4 rows, not 3 (last, last-1, last-2, last-3)
    for i = gui_state.data.last, math.max(gui_state.data.first, gui_state.data.last - 3), -1 do
        local row = gui_state.data[i]
        if row.source == source and (row.type == type or get_setting("combine_different_types")) then
            local frame_diff = GameGetFrameNum() - row.frame
            if frame_diff < (max_frame_diff or 120) then
                List.pop_at(gui_state.data, i)
                return row
            end
        end
    end

    return nil
end

local function format_damage_tooltip(hits)
    local function format_one_type(hits_of_type)
    -- Given a set of hits, formats a tooltip to show in the UI.
    -- For example: {5.4, 6.89, 5.25, 7.25, 4.13, 4.73} rounds to {5, 7, 5, 7, 4, 5} which formats as "2x7, 3x5, 4"
    -- This is fairly complex... we can't sort on the formatted numbers (since "2" > "11" etc), but
    -- we also can't group on the non-formatted numbers (since we want e.g. 6.8 and 7.1 to group together).
        local hit_pairs = {}
        for i = 1, #hits_of_type do
            hit_pairs[i] = { hits_of_type[i], format_number(hits_of_type[i]) }
        end

        -- Sort by highest damage (per hit, not total, so 2x7 comes before 3x5)
        table.sort(hit_pairs, function(a, b) return b[1] < a[1] end )

        -- Group similar hits (hits that format to the same number) as a list of { count, value } pairs
        local groups = {}
        local i = 1
        while i <= #hit_pairs do
            local count = 1
            while hit_pairs[i+1] ~= nil and hit_pairs[i+1][2] == hit_pairs[i][2] do
                count = count + 1
                i = i + 1
            end
            table.insert(groups, { count, hit_pairs[i][2] })
            i = i + 1
        end

        -- Finally, convert to an output string
        -- Not very optimized, but should be fine with such short strings
        local out = ""
        for _, v in ipairs(groups) do
            if v[1] == 1 then
                out = out .. string.format("%s, ", v[2])
            else
                out = out .. string.format("%dx%s, ", v[1], v[2])
            end
        end

        return out:sub(1, #out - 2)
    end

    -- Generate the tooltip for each different damage type in this set of hits
    tooltip = ""
    for type, hits_of_type in pairs(hits) do
        tooltip = tooltip .. type .. ": " .. format_one_type(hits_of_type) .. "\n"
    end

    return tooltip:sub(1, #tooltip - 1) -- Remove trailing newline
end

--- Convert the damage data to what we want to display.
--- This is not done every frame for performance reasons, but rather when the data has changed.
--- If e.g. on fire it WILL currently update every frame, however, since the damage data changes every frame.
function update_gui_data()
    local raw_damage_data = load_damage_data()

    -- Since damage.lua removes all previously read data prior to sending a new batch,
    -- we want to process everything we just received, and don't need to perform any
    -- kinds of checks here.
    for i = raw_damage_data.first, raw_damage_data.last do
        local damage_entry = raw_damage_data[i]

        if damage_entry.damage >= 0 or get_setting("log_healing") then
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

            local display_type = type
            local pooled_damage = 0
            local hits = {}
            local damage_tooltip = nil

            -- Pool/combine damage from some sources, if it happened recently.
            -- Some sources are combined to a single hit, for example fire, toxic sludge, poison and other rapid, recurring damage.
            -- Other sources are combined with the individual hits stored, like multiple quick attacks from the same enemy of the same type.
            -- Multiple attacks of *different* damage types (from one enemy) are combined if the user has that setting enabled (on by default).
            -- Note that the fetch method removes the original damage entry if we are to pool/combine the damage, so we
            -- simply add a new one regardless of whether we should pool/combine or not, and it all works out.
            local source_entry = fetch_pooling_entry(source, type, choice(damage_entry.always_pool, 120, 90))

            if source_entry ~= nil then
                -- Pool/combine this damage into a single row.
                -- The fetch function removed the old entry, so we create a new one (with some info from the old one) and add it.
                hits = source_entry.hits
                pooled_damage = source_entry.total_damage
                if source_entry.type ~= type then
                    display_type = "Multiple" -- TODO: Translation? Use some form of symbols instead of language?
                end
            end

            if hits[type] == nil then
                -- First hit of this type
                hits[type] = {damage_entry.damage}
            elseif damage_entry.always_pool then
                -- Don't store each "hit" separately; instead, increase value of the one that already exists
                hits[type][1] = hits[type][1] + damage_entry.damage
            else
                -- Store the value of each hit
                table.insert(hits[type], damage_entry.damage)
            end

            -- Calculate num_hits here since it needs to be done every frame in the GUI otherwise, and it's a bit involved
            local num_hits = 0
            for _, v in pairs(hits) do
                num_hits = num_hits + #v
            end

            if num_hits > 1 then
                damage_tooltip = format_damage_tooltip(hits)
            end

            List.pushright(gui_state.data, {
                source = source,
                type = display_type,
                damage_text = format_number(damage_entry.damage + pooled_damage),
                total_damage = damage_entry.damage + pooled_damage,
                hits = hits,
                num_hits = num_hits,
                damage_tooltip = damage_tooltip,
                hp = format_number(damage_entry.hp),
                max_hp = format_number(damage_entry.max_hp),
                time = math.floor(damage_entry.time), -- Formatted on display. floor() to make them all update in sync
                frame = damage_entry.frame,
                location = location,
                id = damage_entry.id
            })

            if damage_entry.damage > 0 then
                -- Exclude healing "damage" for this calculation
                gui_state.raw_total_damage = gui_state.raw_total_damage + damage_entry.damage
            end
        end
    end

    if gui_state.raw_total_damage > 0 then
        gui_state.data.total_damage = string.format(" (%s dmg total)", format_number(gui_state.raw_total_damage))
    else
        gui_state.data.total_damage = " (hitless)"
    end

    -- Clean up excessive entries
    while List.length(gui_state.data) > max_rows_allowed do
        List.popleft(gui_state.data)
    end
end

local function activation_hotkey_was_just_pressed()
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
        gui_state.display_gui = not gui_state.display_gui
        if get_setting("force_show_on_load") then
            set_setting("force_show_on_load", false)
        end
    end

    local highest_id_read = tonumber(GlobalsGetValue("damagelog_highest_id_read", "0"))
    local highest_id_written = tonumber(GlobalsGetValue("damagelog_highest_id_written", "0"))
    if highest_id_written > highest_id_read then
        update_gui_data()
    end

    draw_gui()

    if get_setting("show_help_window") then
        draw_help_window()
    end
end

-- Restore the saved data from this run when the game is restarted
function load_saved_gui_data()
    gui_state.raw_total_damage = tonumber(GlobalsGetValue("damagelog_total_damage", "0"))
    gui_state.data = safe_deserialize(GlobalsGetValue("damagelog_saved_gui_data", safe_serialize(List.new())))

    -- Clear all the stored times; they're stored as time since the game last started, so
    -- they will be entirely invalid after a restart
    for i = gui_state.data.first, gui_state.data.last do
        gui_state.data[i].time = -1
    end

    update_gui_data()
end

function save_gui_data()
    GlobalsSetValue("damagelog_total_damage", tostring(gui_state.raw_total_damage))
    GlobalsSetValue("damagelog_saved_gui_data", safe_serialize(gui_state.data))
end

function OnModInit()
    load_settings()

    gui_state = init_gui()
end

function OnPausedChanged(is_paused, is_inventory_pause)
    gui_state.is_paused = is_paused

    if is_paused then
        -- Store the GUI data here in case the player saves and exits
        save_gui_data()
    end

    if is_inventory_pause or display_gui_after_wand_pickup ~= nil then
        if is_paused then
            -- Picking up a wand. Always hide the GUI if it's shown, but show it again afterwards
            -- if it was visible to begin with
            display_gui_after_wand_pickup = gui_state.display_gui
            gui_state.display_gui = false
        else
            -- Wand pickup is completed
            gui_state.display_gui = display_gui_after_wand_pickup
            display_gui_after_wand_pickup = nil
        end
    elseif is_paused then
        -- "Standard" pause, i.e. the escape menu
        if get_setting("auto_show_hide_on_pause") then
            gui_state.display_gui = true
        end
    else
        -- Return from the escape menu
        load_settings()
        if get_setting("auto_show_hide_on_pause") then
            gui_state.display_gui = false
        end
    end
end

function OnPausePreUpdate()
    if get_setting("show_on_pause_screen") then
        handle_input_and_gui()
    end
end

function OnWorldPostUpdate()
    if not initial_setup_completed then
        -- The last damage entry is still stored after processing.
        -- Clear it now (or it will be duplicated in the GUI),
        -- instead of doing this every time we take damage.
        GlobalsSetValue("damagelog_damage_data", safe_serialize(List.new()))

        load_saved_gui_data()
        initial_setup_completed = true
    end

    handle_input_and_gui()
end

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

    gui_state.player_spawn_time = GameGetRealWorldTimeSinceStarted()
end