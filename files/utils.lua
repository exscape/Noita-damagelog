smallfolk = dofile_once("mods/damagelog/smallfolk/smallfolk.lua")

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

-- Roughly equivalent to the ternary operator.
-- Always evaluates every condition, however!
function choice(condition, if_true, if_false)
    if condition then return if_true else return if_false end
end

----- Double ended queue implementation from https://www.lua.org/pil/11.4.html
local List = {}
function List.new ()
  return {first = 0, last = -1}
end

function List.pushleft (list, value)
  local first = list.first - 1
  list.first = first
  list[first] = value
end

function List.pushright (list, value)
  local last = list.last + 1
  list.last = last
  list[last] = value
end

function List.popleft (list)
  local first = list.first
  if first > list.last then error("list is empty") end
  local value = list[first]
  list[first] = nil        -- to allow garbage collection
  list.first = first + 1
  return value
end

function List.popright (list)
  local last = list.last
  if list.first > last then error("list is empty") end
  local value = list[last]
  list[last] = nil         -- to allow garbage collection
  list.last = last - 1
  return value
end

--- Added by exscape
function List.isempty (list)
	return list.first > list.last
end

--- Added by exscape
function List.length (list)
	return list.last - list.first + 1
end

--- Added by exscape
function List.peekright (list)
  local last = list.last
  if list.first > last then error("list is empty") end
  return list[last]
end
----- End double ended queue implementation

-- The wiki for GlobalsSetValue claims that:
-- "Writing a string containing quotation marks can corrupt the `world_state.xml` save file."
-- In case this is still true, let's avoid writing such strings.
function safe_serialize(s)
	local serialized = smallfolk.dumps(s)
  if serialized:find("@") then
    serialized:gsub("@", "")
    log("damagelog Warning: removed @ from string, may cause bugs")
  end
	return (serialized:gsub([["]], [[@]]))
end

function safe_deserialize(s)
	return smallfolk.loads((s:gsub([[@]], [["]])))
end

function store_damage_data(data)
	local serialized = safe_serialize(data)
	GlobalsSetValue("damagelog_damage_data", serialized)
	GlobalsSetValue("damagelog_latest_data_frame", GameGetFrameNum())

	return #serialized
end

local empty_list = safe_serialize(List.new())
function load_damage_data()
	local data = GlobalsGetValue("damagelog_damage_data", empty_list)
	return safe_deserialize(data)
end

return { ["List"] = List }