local Utils = dofile_once("mods/damagelog/files/utils.lua")
local List = Utils.List

-- Generated by a helper mod (damagelog-dev-helper)
local additional_entities = dofile_once("mods/damagelog/files/additional_entities.lua")

local damage_data = List.new() -- All damage that has not yet been received and parsed by the GUI code
local last_damage_entry = nil  -- The very last entry, stored separately as we need it for pooling
local next_hit_id = 1          -- The ID that will be used for the next hit (i.e. no hit with this ID exists yet)

local function get_entity_name(entity_id)
    if entity_id == 0 then
        return "Unknown"
    end

    local entity_raw_name = EntityGetName(entity_id)
    if entity_raw_name == nil or #entity_raw_name <= 0 then
        -- Thus unfortunately happens for some entities, like animals/rainforest/bloom.xml, that use a base entity.
        -- The name is not inherited from the base entity file, so it's left with "" as a name.
        -- Try to look it up in our precomputed lookup table, which contains all such names as of the mod's release.

        local filename = EntityGetFilename(entity_id)
        if filename and #filename > 0 then
            -- if statement is probably useless, but eh
            return additional_entities[filename] or "Unknown"
        else
            return "Unknown"
        end
    -- Handle a few special cases
    elseif entity_raw_name == "DEBUG_NAME:player" then
        return "Player"
    elseif entity_raw_name == "workshop_altar" then
        return "Holy mountain"
    elseif entity_raw_name:sub(1, 1) ~= '$' then
        -- Ugly, but at least it will show up.
        -- Not sure where this happens, but it happened for DEBUG_NAME:player and workshop_altar
        -- prior to handling them as special cases above.
        return entity_raw_name
    end

    local entity_name = GameTextGet(entity_raw_name)
    if entity_name == nil or #entity_name <= 0 then
        return "RAW: " .. tostring(entity_raw_name)
    else
        return entity_name
    end
end

local function get_player_entity()
	local players = EntityGetWithTag("player_unit")
	if #players == 0 then
        return nil
    end

	return players[1]
end

local function get_player_health()
    local player = get_player_entity()
    if player == nil then
        return 0
    end

	local damagemodels = EntityGetComponent(player, "DamageModelComponent")
	if damagemodels == nil or #damagemodels < 1 then
        return 0
    end

    return tonumber(ComponentGetValue(damagemodels[1], "hp"))
end

local function should_pool_damage(source, message)
    -- TODO: expand with other sources
    local sources_to_pool = {
        Fire = 1, Acid = 1, Poison = 1, Drowning = 1, Lava = 1,
        ["Toxic sludge"] = 1, ["Freezing vapour"] = 1, ["Freezing liquid"] = 1,
        ["Holy mountain"] = 1
    }

    if not sources_to_pool[source] or List.isempty(damage_data) then
        return false
    end

    local prev = List.peekright(damage_data)

    if prev.source ~= source or prev.type ~= message then
        -- log("Not pooling: " .. prev.source .. " vs " .. source .. " and " .. prev.type .. " vs " .. message)
        return false
    end

    -- Only one check remaining: whether the previous damage was recent enough.
    -- For fire (and some other effects like cursed area damage), recent enough means within a couple of frames.
    -- For toxic sludge, poison and perhaps others, use a bit longer, since they trigger less often.
    -- Fire uses more than 1-2 frames on purpose, so that if you're constantly getting set on fire and having it
    -- put out, we don't spam the log.
    local frame_diff = GameGetFrameNum() - prev.frame

    if source == "Fire" then
        return frame_diff < 30
    else
        return frame_diff < 120
    end
end

local function damage_source_from_message_only(type)
    -- Most of these will probably never trigger as the entity will be displayed instead of
    -- the damage type, but I'd rather have "Source: drill" shown than "Unknown" just in case.
    local simple_types = { projectile = 1, electricity = 1, explosion = 1, fire = 1, melee = 1,
                           drill = 1, slice = 1, ice = 1, healing = 1, poison = 1, water = 1,
                           drowning = 1, kick = 1, fall = 1 }

    if simple_types[type] then
        return (type:gsub("^%l", string.upper)) -- Uppercased first letter
    elseif type == "radioactive" then
        return "Toxic sludge"
    elseif type == "physicshit" then
        return "Physics"
    else
        return "TYPE: " .. type
    end
end

local function source_and_type_from_entity_and_message(entity_thats_responsible, message)
    local damage_was_from_material = message:find("damage from material: ")
    message = (message:gsub("damage from material: ", ""))
    local damage_type = (message:gsub("^%l", string.upper))

    if entity_thats_responsible ~= 0 then
        -- Show the responsible entity if one exists
        return get_entity_name(entity_thats_responsible), damage_type
    elseif message:sub(1,8) == "$damage_" then
        -- No responsible entity; damage is something like toxic sludge, fire etc.
        -- Show that as the source.
        return damage_source_from_message_only(message:sub(9, #message)), damage_type
    elseif damage_was_from_material then
        return (message:gsub("^%l", string.upper)), damage_type
    else
        -- Should never happen; displayed for debugging purposes so that the mod can be updated
        log("damagelog WARNING: unknown message: " .. tostring(message))
        return "MSG: " .. message, damage_type
    end
end

-- Called by Noita every time the player takes damage
-- Hook is initialized in init.lua
function damage_received(damage, message, entity_thats_responsible, is_fatal, projectile_thats_responsible)
    local source, damage_type = source_and_type_from_entity_and_message(entity_thats_responsible, message)
    damage = damage * 25 -- TODO: use magic number? (GUI_HP_MULTIPLIER)

    local hp_after = get_player_health() * 25 - damage -- TODO: use magic number? (GUI_HP_MULTIPLIER)
    if hp_after < 0 then
         -- Technically a bug? "The gods are very curious"
        hp_after = 0
    elseif hp_after < 1 then
        hp_after = 1
    else
        -- The game GUI seems to do this; our display can show 1 hp extra without flooring first
        hp_after = math.floor(hp_after)
    end

    -- Pool damage from fast sources (like fire, once per frame = 60 times per second),
    -- if the last damage entry was from the same source *AND* it was recent.
    local pooled_damage = 0
    if last_damage_entry ~= nil and should_pool_damage(source, message) then
        pooled_damage = last_damage_entry.damage
    end

    last_damage_entry = {
        source = source,
        type = damage_type,
        damage = damage + pooled_damage,
        hp = hp_after,
        time = GameGetRealWorldTimeSinceStarted(),
        frame = GameGetFrameNum(),
        id = next_hit_id
    }

    -- Clean up old entries from damage_data; i.e. entries that have already been received by the GUI code
    local highest_read = tonumber(GlobalsGetValue("damagelog_highest_id_read", "0"))
    while not List.isempty(damage_data)
          and List.peekleft(damage_data).id <= highest_read do
        List.popleft(damage_data)
    end

    -- Store the data in the list and send it to the GUI
    List.pushright(damage_data, last_damage_entry)
    store_damage_data(damage_data, next_hit_id)
    next_hit_id = next_hit_id + 1
end