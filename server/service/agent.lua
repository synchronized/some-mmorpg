local skynet = require "skynet"
local queue = require "skynet.queue"
local sharemap = require "skynet.sharemap"
local socket = require "skynet.socket"

local syslog = require "syslog"
local protoloader = require "protoloader"
local character_handler = require "agent.character_handler"
local map_handler = require "agent.map_handler"
local aoi_handler = require "agent.aoi_handler"
local move_handler = require "agent.move_handler"
local combat_handler = require "agent.combat_handler"


local gamed = tonumber (...)

local host
local proto_request

--[[
.user {
	fd : integer
	account : integer

	character : character
	world : integer
	map : integer
}
]]

local user

local function send_msg (fd, msg)
	local package = string.pack (">s2", msg)
	socket.write (fd, package)
end

local user_fd
local client_session_map = {}
local client_session_id = 0
local function send_request (name, args)
	client_session_id = client_session_id + 1
	local str = proto_request (name, args, client_session_id)
	send_msg (user_fd, str)
	client_session_map[client_session_id] = { name = name, args = args }
end

local function kick_self ()
	skynet.call (gamed, "lua", "kick", skynet.self (), user_fd)
end

local last_heartbeat_time
local HEARTBEAT_TIME_MAX = 0 -- 60 * 100
local function heartbeat_check ()
	if HEARTBEAT_TIME_MAX <= 0 or not user_fd then return end

	local t = last_heartbeat_time + HEARTBEAT_TIME_MAX - skynet.now ()
	if t <= 0 then
		syslog.warning ("heatbeat check failed")
		kick_self ()
	else
		skynet.timeout (t, heartbeat_check)
	end
end

local traceback = debug.traceback
local REQUEST
local function handle_request (name, args, response)
	local f = REQUEST[name]
	if f then
		local ok, ret = xpcall (f, traceback, args)
		if not ok then
			syslog.warningf ("handle message(%s) failed : %s", name, ret) 
			kick_self ()
		else
			last_heartbeat_time = skynet.now ()
			if response and ret then
				send_msg (user_fd, response (ret))
			end
		end
	else
		syslog.warningf ("unhandled message : %s", name)
		kick_self ()
	end
end

local RESPONSE
local function handle_response (id, args)
	local s = client_session_map[id]
	if not s then
		syslog.warningf ("client_session_id: %d not found", id)
		kick_self ()
		return
	end

	local f = RESPONSE[s.name]
	if not f then
		syslog.warningf ("client_session_id: %d unhandled response: %s", id, s.name)
		kick_self ()
		return
	end

	local ok, ret = xpcall (f, traceback, s.args, args)
	if not ok then
		syslog.warningf ("client_session_id: %d handle response(%s) failed: %s", id, s.name, ret) 
		kick_self ()
	end
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		return host:dispatch (msg, sz)
	end,
	dispatch = function (_, _, type, ...)
		if type == "REQUEST" then
			handle_request (...)
		elseif type == "RESPONSE" then
			handle_response (...)
		else
			syslog.warningf ("invalid message type : %s", type) 
			kick_self ()
		end
		skynet.ret();
	end,
}

local CMD = {}

function CMD.open (fd, account_id)
	skynet.error(string.format ("agent account_id: %d has created", account_id))

	user = { 
		fd = fd, 
		account_id = account_id,
		REQUEST = {},
		RESPONSE = {},
		CMD = CMD,
		send_request = send_request,
	}
	user_fd = user.fd
	REQUEST = user.REQUEST
	RESPONSE = user.RESPONSE
	
	character_handler:register(user)

	last_heartbeat_time = skynet.now ()
	heartbeat_check ()
end

function CMD.close ()
	syslog.debug ("agent closed")
	
	local account_id
	if user then
		account_id = user.account_id

		if user.map then
			skynet.call (user.map, "lua", "character_leave")
			user.map = nil
			map_handler:unregister (user)
			aoi_handler:unregister (user)
			move_handler:unregister (user)
			combat_handler:unregister (user)
		end

		if user.world then
			skynet.call (user.world, "lua", "character_leave", user.character.id)
			user.world = nil
		end

		character_handler.save (user.character)

		user = nil
		user_fd = nil
		REQUEST = nil
	end

	skynet.call (gamed, "lua", "close", skynet.self (), account_id)
end

function CMD.kick ()
	error ()
	syslog.debug ("agent kicked")
	skynet.call (gamed, "lua", "kick", skynet.self (), user_fd)
end

function CMD.world_enter (world)
	skynet.error(string.format("agent character: %d(%s) world enter", user.character.id, user.character.general.name))

	character_handler.on_enter_world(user.character)

	user.world = world
	character_handler:unregister(user)

	return user.character.general.map, user.character.movement.pos
end

function CMD.map_enter (map)
	user.map = map

	map_handler:register (user)
	aoi_handler:register (user)
	move_handler:register (user)
	combat_handler:register (user)
end

skynet.start (function ()
	local protod = skynet.uniqueservice ("protod")
	local protoindex = skynet.call(protod, "lua", "loadindex", protoloader.GAME)
	host, proto_request = protoloader.loadbyserver (protoindex)
	
	skynet.dispatch ("lua", function (session, source, command, ...)
		skynet.error(string.format("agent receive lua message session: %d, source: %d, command:%s", session, source, command))
		local f = CMD[command]
		if not f then
			syslog.warningf ("    unhandled message(%s)", command) 
			return skynet.ret ()
		end

		local ok, ret = xpcall (f, traceback, ...)
		if not ok then
			syslog.warningf ("    handle message(%s) failed : %s", command, ret) 
			kick_self ()
			return skynet.ret ()
		end
		skynet.retpack (ret)
	end)
end)

