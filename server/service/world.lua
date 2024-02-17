local skynet = require "skynet"

local log = require "log"

local mapdata = require "gddata.map"

local CMD = {}
local map_instance = {}
local online_character = {}

function CMD.kick (character)
	local userdata = online_character[character]
	if userdata then
		skynet.call (userdata.agent, "lua", "kick")
		online_character[character] = nil
	end
end

function CMD.character_enter (agent, character_id, map, pos)
	if online_character[character_id] ~= nil then
		log ("multiple login detected, character_id %d", character_id)
		CMD.kick (character_id)
		return
	end

	local userdata = { agent = agent, character_id = character_id, map = map}
	online_character[character_id] = userdata
	local m = map_instance[map]
	if not m then
		log ("agent map not found map: %s", map)
		CMD.kick (character_id)
		return
	end

	log ("character(%d) enter world", character_id)
	skynet.call (agent, "lua", "world_enter", skynet.self ())

	skynet.call (m, "lua", "character_enter", agent, character_id, pos)
end

function CMD.character_leave (agent, character_id)
	log ("character(%d) leave world", character_id)
	local userdata = online_character[character_id]
	if userdata then
		online_character[character_id] = nil
		skynet.call (userdata.agent, "lua", "world_leave", userdata.character_id)
	end
end

skynet.start (function ()
	local self = skynet.self ()
	for _, conf in pairs (mapdata) do
		local name = conf.name
		local s = skynet.newservice ("map", self)
		skynet.call (s, "lua", "init", conf)
		map_instance[name] = s
	end
	
	skynet.dispatch ("lua", function (_, source, command, ...)
		local f = assert (CMD[command])
		skynet.retpack (f (source, ...))
	end)
end)
