dofile_once("mods/damagelog/files/utils.lua")

local total_damage = 0
local latest_damage_time = -1
local latest_damage_frame = -1
local latest_print_frame = -1

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
    current_frame = GameGetFrameNum()
    latest_damage_frame = current_frame
    total_damage = total_damage + damage
    latest_damage_time = GameGetRealWorldTimeSinceStarted()

    if current_frame - latest_print_frame >= 60 then
    -- TODO!! Always nil-check before GameTextGet, Entity may not return something useful
      log("#=" .. tostring(damage) .. ", entity=" .. get_entity_name(entity_thats_responsible) .. ", proj=" .. tostring(projectile_thats_responsible) ..  ", msg=" .. translate_message(message))
      log("TOTAL damage " .. tostring(total_damage) .. ", frame num " .. tostring(latest_damage_frame) .. ", time " .. latest_damage_time)
      latest_print_frame = latest_damage_frame
      total_damage = 0
    end
end