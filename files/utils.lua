smallfolk = dofile_once("mods/damagelog/files/smallfolk/smallfolk.lua")
dofile_once("mods/damagelog/files/list.lua")

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
    GamePrint("damagelog: " .. tostring(s))
end

-- Roughly equivalent to the ternary operator.
-- Always evaluates every condition, however!
function choice(condition, if_true, if_false)
    if condition then return if_true else return if_false end
end

function format_time(time, lower_accuracy)
    local current_time = GameGetRealWorldTimeSinceStarted()
    local diff = math.floor(current_time - time)
    if time < 0 or diff < 0 then
        return "?"
    elseif (not lower_accuracy and diff < 1) or (lower_accuracy and diff < 3) then
        -- lower_accuracy is used by e.g. toxic sludge stains, so that the time
        -- doesn't keep jumping between now -> 1s -> 2s -> now -> ... while stained
        return "now"
    elseif diff < 60 then
        return string.format("%.0fs", diff)
    elseif diff < 300 then
        local min, sec = math.floor(diff / 60), math.floor(diff % 60)
        return string.format("%.0fm %.0fs", min, sec)
    elseif diff < 7200 then
        -- Don't show seconds since it's mostly annoying at this point
        return string.format("%.0fm", diff / 60)
    else
        local hr, min = math.floor(diff / 3600), math.floor((diff % 3600) / 60)
        return string.format("%.0fh %.0fm", hr, min)
    end
end

-- Uses a simple human-readable format for only partially insane numbers (millions, billions).
-- Reverts to scientific notation shorthand (e.g. 1.23e14) for the truly absurd ones.
 function format_number(n)
    if n < 1000000 then -- below 1 million, show as plain digits e.g. 987654
        -- Format, and prevent string.format from rounding to 0
        local formatted = string.format("%.0f", n)
        if formatted == "0" and n > 0 then
            formatted = "<1"
        end
        return formatted
    elseif n < 1000000000 then
        -- Below 1 billion, show as e.g. 123.4M
        return string.format("%.4gM", n/1000000)
    elseif n < 1000000000000 then
        -- Below 1 trillion, show as e.g. 123.4B
        return string.format("%.4gB", n/1000000000)
    else
        -- Format to exponent notation, and convert e.g. 1.3e+007 to 1.3e7
        return (string.format("%.4g", n):gsub("e%+0*", "e"))
    end
end

-- The wiki for GlobalsSetValue claims that:
-- "Writing a string containing quotation marks can corrupt the `world_state.xml` save file."
-- In case this is still true, let's avoid writing such strings.
function safe_serialize(s)
    local serialized = smallfolk.dumps(s)
    if serialized:find("§") then
        log("WARNING: string contains §:")
        log(serialized)
        serialized = serialized:gsub("§", "")
        log("Warning: removed § from string, may cause bugs")
    end
    return (serialized:gsub([["]], [[§]]))
end

function safe_deserialize(s)
    return smallfolk.loads((s:gsub([[§]], [["]])), 40000)
end

function store_damage_data(data, max_id)
    local serialized = safe_serialize(data)
    GlobalsSetValue("damagelog_damage_data", serialized)
    GlobalsSetValue("damagelog_highest_id_written", tostring(max_id))
end

local empty_list = safe_serialize(List.new())

function load_damage_data()
    local data = GlobalsGetValue("damagelog_damage_data", empty_list)
    local damage_data = safe_deserialize(data)

    local max_id = 0
    if not List.isempty(damage_data) then
        max_id = List.peekright(damage_data).id
    end

    if max_id ~= 0 then
        -- max_id will be 0 from when you start (after load or new game) until you take damage,
        -- so don't reset highest_id_read, or update_gui_data will run every frame for no reason
        GlobalsSetValue("damagelog_highest_id_read", tostring(max_id))
    end

    return damage_data
end

function clamp(v, min, max)
    if v < min then return min
    elseif v > max then return max
    else return v end
end

-- Ugly? Yes. But Lua doesn't support these characters for string.upper
-- This is a complete list of the non-ASCII characters used as a first letter in Noita as of this writing,
-- except for Chinese/Japanese/Korean, which we can't display anyway due to a lack of supported fonts.
local lc_uc_map = { ["р"] = "Р", ["в"] = "В", ["б"] = "Б", ["у"] = "У", ["о"] = "О", ["с"] = "С", ["п"] = "П", ["э"] = "Э", ["é"] = "É", ["л"] = "Л", ["ф"] = "Ф", ["я"] = "Я", ["ш"] = "Ш", ["н"] = "Н", ["и"] = "И", ["á"] = "Á", ["а"] = "А", ["з"] = "З", ["ü"] = "Ü", ["к"] = "К", ["г"] = "Г", ["ś"] = "Ś", ["ż"] = "Ż", ["м"] = "М", ["д"] = "Д", ["х"] = "Х", ["ł"] = "Ł", ["ж"] = "Ж", ["т"] = "Т", ["ч"] = "Ч", ["ц"] = "Ц" }

function initialupper(s)
    -- All relevant characters are 2-byte characters, and since Lua doesn't support UTF-8, we need to fetch the first two bytes
    local uc = lc_uc_map[s:sub(1, 2)]
    if uc ~= nil then
        return uc .. s:sub(3, #s) -- Same deal here
    else
        return (s:gsub("^%l", string.upper))
    end
end