smallfolk = dofile_once("mods/damagelog/smallfolk/smallfolk.lua")

local test_shared = {}

function dump(o)
	if type(o) == 'table' then
	   local s = '{ '
	   for k,v in pairs(o) do
		  if type(k) ~= 'number' then k = '"'..k..'"' end
		  s = s .. '['..k..'] = ' .. dump(v) .. ','
	   end
	   return s .. '} '
	else
	   return tostring(o)
	end
 end

function log(s)
	print("!!! damagelog !!! " .. tostring(s))
	GamePrint("!!! " .. tostring(s))
end

-- The wiki for GlobalsSetValue claims that:
-- "Writing a string containing quotation marks can corrupt the `world_state.xml` save file."
-- In case this is still true, let's avoid writing such strings.
function safe_serialize(s)
	local serialized = smallfolk.dumps(s)
--	log("safe_serialize BEFORE gsub, original data is: " .. serialized)
	return (serialized:gsub([["]], [[!]]))
end

function safe_deserialize(s)
	return smallfolk.loads((s:gsub([[!]], [["]])))
end

function store_damage_data(data)
	local serialized = safe_serialize(data)
--	log("STORING DATA: " .. serialized)
	GlobalsSetValue("damagelog_damage_data", serialized)
	GlobalsSetValue("damagelog_latest_data_frame", GameGetFrameNum())

	return #serialized
end

function load_damage_data()
	local data = GlobalsGetValue("damagelog_damage_data", "{}")
--	log("DATA STORED in globals IS: " .. data)
	return safe_deserialize(data)
end

return test_shared