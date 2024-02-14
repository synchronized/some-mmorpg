local skynet = require "skynet"
local driver = require "skynet.socketdriver"

local gateserver = require "gameserver.gateserver"
local syslog = require "syslog"
local protoloader = require "protoloader"



local gameserver = {}
local pending_msg = {}
local login_token = {}

local host

local function send_msg (fd, msg)
	local package = string.pack (">s2", msg)
	driver.send (fd, package)
end

function gameserver.forward (fd, agent)
	gateserver.forward (fd, agent)
end

function gameserver.kick (fd)
	gateserver.close_client (fd)
end

function gameserver.start (gamed)
	local handler = {}

	function handler.open (source, conf)

		local protod = skynet.uniqueservice ("protod")
		local protoindex = skynet.call(protod, "lua", "loadindex", protoloader.GAME)
		host = protoloader.loadbyserver (protoindex)

		return gamed.open (conf)
	end

	function handler.connect (fd, addr)
		syslog.noticef ("connect from %s (fd = %d)", addr, fd)
		gateserver.open_client (fd)
	end

	function handler.disconnect (fd)
		syslog.noticef ("fd (%d) disconnected", fd)
	end

	local function do_login (fd, msg, sz)
		local type, name, args, response = host:dispatch (msg, sz)
		assert (type == "REQUEST")
		assert (name == "login")
		assert (args, "invalid request")
		assert (args.login_session, "invalid request login_session")
		assert (args.token, "invalid request token")

		local login_session = assert(tonumber (args.login_session),
			string.format("invalid request login_session: %d", args.login_session))
		local account_id = gamed.auth_handler (login_session, args.token)
		send_msg (fd, response ({
			success = account_id ~= nil,
		}))
		return assert(account_id,
			string.format("login_session: %d auth verify failed", login_session))
	end

	local traceback = debug.traceback
	function handler.message (fd, msg, sz)
		local queue = pending_msg[fd]
		if queue then
			table.insert (queue, { msg = msg, sz = sz })
		else
			pending_msg[fd] = {}

			local ok, account_id = xpcall (do_login, traceback, fd, msg, sz)
			if ok then
				syslog.noticef ("<login> login account_id: %d login success", account_id)
				
				local agent = gamed.login_handler (fd, account_id)
				queue = pending_msg[fd]
				for _, t in pairs (queue) do
					syslog.noticef ("    forward pending message to agent %d", agent)
					skynet.rawcall(agent, "client", t.msg, t.sz)
				end
			else
				syslog.warningf ("    login failed : %s", account_id)
				gateserver.close_client (fd)
			end

			pending_msg[fd] = nil
		end
	end

	local CMD = {}

	function CMD.token (id, secret)
		local id = tonumber (id)
		login_token[id] = secret
		skynet.timeout (10 * 100, function ()
			if login_token[id] == secret then
				syslog.noticef ("account %d token timeout", id)
				login_token[id] = nil
			end
		end)
	end

	function handler.command (cmd, ...)
		local f = CMD[cmd]
		if f then
			return f (...)
		else
			return gamed.command_handler (cmd, ...)
		end
	end

	return gateserver.start (handler)
end

return gameserver
