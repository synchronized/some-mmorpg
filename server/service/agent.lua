local skynet = require "skynet"

local service = require "service"
local client = require "client"
local log = require "log"

local protoloader = require "protoloader"
local character_handler = require "agent.character_handler"
local map_handler = require "agent.map_handler"
local aoi_handler = require "agent.aoi_handler"
local combat_handler = require "agent.combat_handler"

local cjsonutil = require "cjson.util"

local traceback = debug.traceback

--[[
.user {
	fd : integer
	account_id : integer

	character : character
	world : integer
	map : integer
}
]]

local user = {}

local cli = client.handler()

function cli:ping()
	-- log ("account_id: %d ping", tonumber(user.account_id))
	return nil
end

local function kick_agent ()
	if user.account_id then
		log ("agent kicked")
		skynet.call(service.manager, "lua", "kick", user.account_id)	-- report exit
	end
end

local last_heartbeat_time
local HEARTBEAT_TIME_MAX = 0 -- 60 * 100
local function heartbeat_check ()
	if HEARTBEAT_TIME_MAX <= 0 or not user.fd then return end

	local t = last_heartbeat_time + HEARTBEAT_TIME_MAX - skynet.now ()
	if t <= 0 then
		log ("heatbeat check failed")
		kick_agent ()
	else
		skynet.timeout (t, heartbeat_check)
	end
end

local agent = {
	-- CMD = {}
}

local function new_user()
	assert(user, string.format("invalid user data"))
	local fd = user.fd
	local ok, error = pcall(client.dispatch, user)
	log("fd=%d is gone. error = %s", fd, tostring(error))
	client.close(fd)
	if user.fd == fd then
		user.fd = nil
		skynet.sleep(1000)	-- exit after 10s
		if user.fd == nil then
			-- double check
			if not user.exit then
				user.exit = true	-- mark exit
				kick_agent()
				log("user %s afk", user.account_id)
			end
		end
	end
end

function agent.assign (fd, account_id)
	if user.fd then
		error(string.format(
			"agent repeat assign account_id: %d, new account_id: %d", 
			user.account_id, account_id))
	end

	log ("agent account_id: %d has created", account_id)

	if user.account_id == account_id then
		user.fd = fd
		user.exit = nil
	else
		user = {
			fd = fd, 
			account_id = account_id,
			REQUEST = {},
			RESPONSE = {},
			CMD = {},
		}
	end

	agent.CMD = user.CMD
	
	character_handler:register(user)

	last_heartbeat_time = skynet.now ()
	heartbeat_check ()

	skynet.fork(new_user)
	return true
end

function agent.close()
	log.printf ("agent closed account_id: %d", user.account_id)
	
	if user.account_id then
		local account_id = user.account_id
		if user.map then
			skynet.call (user.map, "lua", "character_leave", user.character.id)
		end

		if user.world then
			skynet.call (user.world, "lua", "character_leave", user.character.id)
		end

		character_handler.save (user.character)

		user = {}
		agent.CMD = nil

		skynet.call (service.manager, "lua", "exit", account_id)
	end
end

function agent.kick ()
	kick_agent()
end

function agent.world_enter (world)
	log ("agent character: %d(%s) world enter", 
		user.character.id, user.character.general.name)

	user.world = world
	character_handler:unregister(user)
end

function agent.world_leave (character_id)
	if user.character and user.character.id == character_id then
		log ("agent character: %d(%s) world leave", 
			user.character.id, user.character.general.name)
		user.world = nil
	end
end

function agent.map_enter (map)
	log ("agent character: %d(%s) map enter", 
		user.character.id, user.character.general.name)

	user.map = map

	map_handler:register (user)
	aoi_handler:register (user)
	combat_handler:register (user)
end

function agent.map_leave (character_id)
	if user.character and user.character.id == character_id then
		log ("agent character: %d(%s) map leave", 
			user.character.id, user.character.general.name)
		user.map = nil
		map_handler:unregister (user)
		aoi_handler:unregister (user)
		combat_handler:unregister (user)
	end
end

service.init {
	command = agent,
	-- info = data,
	require = {
		"manager",
	},
	init = client.init (protoloader.GAME),
}