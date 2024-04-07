dofile_once("mods/damagelog/files/utils.lua")

local damage_data = {  }

function get_entity_name(entity_id)
    local entity_name = EntityGetName(entity_id)
    if entity_name == nil or #entity_name <= 0 then
        return "Unknown"
    end

    if entity_name == "DEBUG_NAME:player" then
        return "Player"
    end

    local translated = GameTextGet(entity_name)
    if translated == nil or #translated <= 0 then
        return "RAW: " .. tostring(entity_name)
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

function lookup_damage_type(type)
    -- Most of these will probably never trigger as the entity will be displayed instead of
    -- the damage type, but I'd rather have "Source: drill" shown than "Unknown" just in case.
    local simple_types = { projectile = 1, electricity = 1, explosion = 1, fire = 1, melee = 1,
                           drill = 1, slice = 1, ice = 1, healing = 1, poison = 1, water = 1,
                           drowning = 1, kick = 1, fall = 1 }

    local source
    if simple_types[type] then
        source = (type:gsub("^%l", string.upper)) -- Uppercased first letter
    elseif type == "radioactive" then
        source = "Toxic sludge"
    elseif type == "physicshit" then
        source = "Physics"
    elseif type == "holy_mountains_curse" then
        source = "Holy mountain curse"
    else
        source = "TYPE: " .. type
    end

    return source
end

function get_player_entity()
	local players = EntityGetWithTag("player_unit")
	if #players == 0 then
        return nil
    end

	return players[1]
end

function get_player_health()
    local player = get_player_entity()
    if player == nil then
        return 0
    end

	local damagemodels = EntityGetComponent( get_player_entity(), "DamageModelComponent" )
	local health = 0
	if damagemodels ~= nil then
		for _,v in ipairs(damagemodels) do
			health = tonumber( ComponentGetValue( v, "hp" ) )
			break
		end
	end
	return health
end

-- Called by Noita every time the player takes damage
-- Hook is initialized in init.lua
function damage_received( damage, message, entity_thats_responsible, is_fatal, projectile_thats_responsible)
    damage = damage * 25 -- TODO: use magic number? (GUI_HP_MULTIPLIER)

    local damage_was_from_material = message:find("damage from material: ")
    message = (message:gsub("damage from material: ", ""))

    local source
    if entity_thats_responsible ~= 0 then
        -- Show the responsible entity if one exists
        source = get_entity_name(entity_thats_responsible)
    elseif message:sub(1,8) == "$damage_" then
        -- No responsible entity; damage is something like toxic sludge, fire etc.
        -- Show that as the source.
        source = lookup_damage_type(message:sub(9, #message))
    elseif damage_was_from_material then
        source = (message:gsub("^%l", string.upper))
    else
        -- Should never happen; displayed for debugging purposes so that the mod can be updated
        source = "MSG: " .. message
        log("damagelog WARNING: unknown message: " .. tostring(message))
    end

    local damage_type = message
    local hp_after = get_player_health() * 25 - damage -- TODO: use magic number? (GUI_HP_MULTIPLIER)
    if hp_after < 0 then hp_after = 0 end

    table.insert(damage_data, {
        source,
        damage_type,
        damage,
        hp_after,
        GameGetRealWorldTimeSinceStarted()
    })

    -- TODO: don't save data EVERY frame if we're on fire; pool the data here, not in init.lua
    -- TODO: sources of every-frame damage include AT LEAST: fire, dragon bit[e?], cursed rock field, possibly piercing
    -- TODO: use a deque here!
      local data_points = #damage_data
      local serialized_length = store_damage_data(damage_data)

      -- TODO: data_points shouldn't surpass something like 50-60 if we add scrolling, or 10 if we don't!
      -- TODO: serialized_length must not surpass 10000, start cutting down if we reach say 8000
end