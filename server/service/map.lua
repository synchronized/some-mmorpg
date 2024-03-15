local skynet = require "skynet"

local log = require "log"

local aoi = require "map.aoi"

local conf

local pending_character = {}
local online_character = {}
local CMD = {}

function CMD.init (w, c)
	conf = c
	aoi.init (conf.bbox, conf.radius)
end

function CMD.character_enter (_, agent, character_id)
	log ("character_id(%d) loading map", character_id)

	pending_character[character_id] = {agent = agent, character_id = character_id}
	skynet.call (agent, "lua", "map_enter", skynet.self (), character_id)
end

function CMD.character_leave (agent, character_id)
	local userdata = online_character[character_id] or pending_character[character_id]
	if userdata and userdata.agent == agent then
		log ("character_id(%d) leave map", character_id)
		local ok, list = aoi.remove (agent)
		if ok then
			skynet.call (agent, "lua", "aoi_manage", nil, list)
		end
		skynet.call(agent, "lua", "map_leave", character_id)
		online_character[agent] = nil
		pending_character[agent] = nil
	end
end

function CMD.character_ready (agent, pos)
	local userdata = pending_character[agent]
	if userdata == nil then
		log ("<error> agent(%d) is not pending status", agent)
		return false
	end
	online_character[agent] = userdata
	pending_character[agent] = nil

	log ("character_id(%d) enter map", userdata.character_id)

	local ok, list = aoi.insert (agent, pos)
	if not ok then
		log ("<error> character_id(%d) join aoi manager failed", userdata.character_id)
		return false
	end

	skynet.call (agent, "lua", "aoi_manage", list)
	return true
end

function CMD.move_blink (agent, pos)
	local ok, add, update, remove = aoi.update (agent, pos)
	if not ok then
		log ("<error> aoi update failed")
		return false
	end
	skynet.call (agent, "lua", "aoi_manage", add, remove, update, "move")
	return true
end

skynet.start (function ()
	skynet.dispatch ("lua", function (_, source, command, ...)
		local f = assert (CMD[command])
		skynet.retpack (f (source, ...))
	end)
end)
