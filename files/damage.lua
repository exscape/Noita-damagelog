List = dofile_once("mods/damagelog/files/utils.lua")

local damage_data = List.new()

function get_entity_name(entity_id)
    if entity_id == 0 then
        return "Unknown"
    end

    local entity_name = EntityGetName(entity_id)
    if entity_name == nil or #entity_name <= 0 then
        -- Unfortunately happens for some entities, like animals/rainforest/bloom.xml, that use a base entity
        --[[
        local file = EntityGetFilename(entity_id)
        log("Entity filename: " .. file)
        local data = ModTextFileGetContent(file)
        log("READ FROM XML: " .. tostring(data))
        ]]

        return "TODO: XML PARSE"
    elseif entity_name == "DEBUG_NAME:player" then
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

function should_pool_damage(source, message)
    -- TODO: expand with other sources
    if (source ~= "Fire" and source ~= "Toxic sludge") or List.isempty(damage_data) then
        return false
    end

    local prev = List.peekright(damage_data)

    if prev[1] ~= source then
        return false
    end

    -- Only one check remaining: whether the previous damage was recent enough.
    -- For fire (and some other effects like cursed area damage), recent enough means within a couple of frames.
    -- For toxic sludge, poison and perhaps others, use a bit longer, since they only seem to fire about (exactly)?
    -- once a second.
    -- Fire uses more than 1-2 frames on purpose, so that if you're constantly getting set on fire and having it
    -- put out, we don't spam the log.
    local frame_diff = GameGetFrameNum() - prev[6]

    if source == "Fire" then return frame_diff < 30
    else return frame_diff < 120
    end
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

    -- Pool damage from fast sources (like fire, once per frame = 60 times per second),
    -- if the last damage entry was from the same source *AND* it was recent.
    if should_pool_damage(source, message) then
        local prev = List.popright(damage_data)
        damage = damage + prev[3]
    end

    List.pushright(damage_data, {
        source,
        damage_type,
        damage,
        hp_after,
        GameGetRealWorldTimeSinceStarted(),
        GameGetFrameNum()
    })

    while damage_data.last - damage_data.first >= 10 do
        -- Limit the list to 10 entries.
        -- Should never need to run more than once, but why shouldn't I use a loop...?
        List.popleft(damage_data)
    end

    len = store_damage_data(damage_data)
    -- TODO: don't save data EVERY frame if we're on fire; pool the data here, not in init.lua
    -- TODO: sources of every-frame damage include AT LEAST: fire, dragon bit[e?], cursed rock field, possibly piercing
    -- TODO: use a deque here!

      -- TODO: data_points shouldn't surpass something like 50-60 if we add scrolling, or 10 if we don't!
      -- TODO: serialized_length must not surpass 10000, start cutting down if we reach say 8000
end