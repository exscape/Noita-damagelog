--[[
function OnModPreInit()
end
function OnModInit()
end
function OnModPostInit()
end
]]--

dofile_once("mods/damagelog/files/utils.lua")
local damage_callback_added = false

-- TODO: Use EntityGetComponent to ACTUALLY properly check, and remove damage_callback_added

function OnPlayerSpawned(player_entity)
	if damage_callback_added then
		log("!!!!!!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called even though we have added the callback, IGNORING")
	end
	if player_entity ~= nil then
		log("!!!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called successfully, adding damage.lua callback!")
        EntityAddComponent(player_entity, "LuaComponent", {
            script_damage_received = "mods/damagelog/files/damage.lua"
        })
		damage_callback_added = true
	else
	log("!!!!!!!!!!!!!!!!!!! OnPlayerSpawned called BUT player_unit not found!!!")
    end
end
