dofile_once("mods/damagelog/files/utils.lua")

local damage_data = {  }

--[[
LUA: !!! damagelog !!! #=0.25, entity=453, proj=0, msg=$damage_melee
LUA: !!! damagelog !!! #=0.25, entity=443, proj=0, msg=$damage_melee
LUA: !!! damagelog !!! #=0.079999998211861, entity=0, proj=0, msg=$damage_radioactive
LUA: !!! damagelog !!! #=0.0013333252863958, entity=0, proj=0, msg=$damage_fire
]]
function get_entity_name(entity_id)
    local entity_name = EntityGetName(entity_id)
    if entity_name == nil or #entity_name <= 0 then
        return "Unknown"
    end

    local translated = GameTextGet(entity_name)
    if translated == nil or #translated <= 0 then
        return "Unknown"
    else
        return translated
    end
end

function translate_message(message)
    if #message < 1 then
        return "-"
    elseif string.sub(message, 1, 1) == "$" then
        return "Translated: " .. GameTextGet(message)
    else
        return message
    end
end

function damage_received( damage, message, entity_thats_responsible, is_fatal, projectile_thats_responsible)
    damage = damage * 25 -- TODO: use magic number?
--    current_frame = GameGetFrameNum()

--      log("#=" .. tostring(damage) .. ", entity=" .. get_entity_name(entity_thats_responsible) .. ", proj=" .. tostring(projectile_thats_responsible) ..  ", msg=" .. translate_message(message))
--      log("TOTAL damage " .. tostring(total_damage) .. ", frame num " .. tostring(latest_damage_frame) .. ", time " .. latest_damage_time)

    local hp_after = 0

    log("Inserting " .. tostring(damage) .. " damage at frame " .. tostring(GameGetFrameNum()))
    table.insert(damage_data, {
        get_entity_name(entity_thats_responsible), -- TODO: fix the first two columns
        message,
        damage,
        hp_after,
        GameGetRealWorldTimeSinceStarted()
    })

      -- TODO: don't save data EVERY frame if we're on fire; pool the data here, not in init.lua
      -- TODO: sources of every-frame damage include AT LEAST: fire, dragon bit[e?], cursed rock field, possibly piercing

      -- TODO: use a deque here!
      store_damage_data(damage_data)
end

return damage_data