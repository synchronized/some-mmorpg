local skynet = require "skynet"
local socket = require "skynet.socket"

local syslog = require "syslog"
local protoloader = require "protoloader"
local srp = require "srp"
local aes = require "aes"
local uuid = require "uuid"

local traceback = debug.traceback

local master
local database
local host
local auth_timeout
local session_expire_time
local session_expire_time_in_second
local connection = {}
local saved_session = {}

local slaved = {}

local CMD = {}

function CMD.init (m, id, conf)
	master = m
	database = skynet.uniqueservice ("database")
	
	local protod = skynet.uniqueservice ("protod")
	local protoindex = skynet.call (protod, "lua", "loadindex", protoloader.LOGIN)
	host = protoloader.loadbyserver (protoindex)

	auth_timeout = conf.auth_timeout * 100
	session_expire_time = conf.session_expire_time * 100
	session_expire_time_in_second = conf.session_expire_time
end

local function close (fd)
	if connection[fd] then
		socket.close (fd)
		connection[fd] = nil
	end
end

local function read (fd, size)
	return socket.read (fd, size) or error ()
end

local function read_msg (fd)
	local s = read (fd, 2)
	local size = s:byte(1) * 256 + s:byte(2)
	local msg = read (fd, size)
	return host:dispatch (msg, size)
end

local function send_msg (fd, msg)
	local package = string.pack (">s2", msg)
	socket.write (fd, package)
end

function CMD.auth (fd, addr)
	connection[fd] = addr
	skynet.timeout (auth_timeout, function ()
		if connection[fd] == addr then
			syslog.warningf ("connection %d from %s auth timeout!", fd, addr)
			close (fd)
		end
	end)

	socket.start (fd)
	socket.limit (fd, 8192)

	local type, name, args, response = read_msg (fd)
	assert (type == "REQUEST")

	if name == "handshake" then
		-- handshake
		assert (args, "invalid handshake request")
		assert (args.username, "invalid handshake request username")
		assert (args.client_pub, "invalid handshake request client_pub")
		local username = args.username
		skynet.error(string.format("<login> handshake username: %s", username))

		local account = assert(skynet.call (database, "lua", "account", "load", username),
			"load account username: " .. username .. " failed")

		local session_key, _, pkey = srp.create_server_session_key (account.verifier, args.client_pub)
		local challenge = srp.random ()
		local msg = response {
			user_exists = (account.account_id ~= nil),
			salt = account.salt,
			server_pub = pkey,
			challenge = challenge,
		}
		send_msg (fd, msg)

		-- auth
		type, name, args, response = read_msg (fd)
		assert (type == "REQUEST" and name == "auth" and args and args.challenge, "invalid auth request")

		local text = aes.decrypt (args.challenge, session_key)
		assert (challenge == text, "auth challenge failed")

		skynet.error(string.format("<login> auth username: %s", username))

		local account_id = tonumber (account.account_id)
		if not account_id then
			assert (args.password)
			account_id = uuid.gen ()
			local password = aes.decrypt (args.password, session_key)
			account.account_id = assert(skynet.call (database, "lua", "account", "create", account_id, username, password),
				string.format ("create account %s/%d failed", username, account_id))

			skynet.error(string.format("    account username: %s account_id: %d create", username, account_id))
		else
			skynet.error(string.format("    account username: %s account_id: %d login", username, account_id))
		end
		
		challenge = srp.random ()
		local login_session = skynet.call (master, "lua", "save_session", account_id, session_key, challenge)

		skynet.error(string.format("    account username: %s account_id: %d login_session: %d", username, account_id, login_session))

		msg = response {
			login_session = login_session,
			expire = session_expire_time_in_second,
			challenge = challenge,
		}
		send_msg (fd, msg)
		
		type, name, args, response = read_msg (fd)
		assert (type == "REQUEST")
	end

	-- challenge
	assert (name == "challenge")
	assert (args and args.login_session and args.challenge)

	local token, challenge = skynet.call (master, "lua", "challenge", args.login_session, args.challenge)
	assert (token and challenge)

	local msg = response {
		token = token,
		challenge = challenge,
	}
	send_msg (fd, msg)

	close (fd)
end

function CMD.save_session (login_session, account_id, session_key, challenge)
	skynet.error(string.format("    account account_id: %d, login_session: %d savesession ", account_id, login_session))

	saved_session[login_session] = { account_id = account_id, key = session_key, challenge = challenge }
	skynet.timeout (session_expire_time, function ()
		local t = saved_session[login_session]
		if t then
			if t and t.key == key then
				saved_session[login_session] = nil
			end
		end
	end)
end

function CMD.challenge (login_session, secret)
	skynet.error(string.format("    account login_session: %d verify challenge secret", login_session))

	local t = saved_session[login_session] or error ()

	local text = aes.decrypt (secret, t.key) or error ()
	assert (text == t.challenge)

	t.token = srp.random ()
	t.challenge = srp.random ()

	return t.token, t.challenge
end

function CMD.verify (login_session, secret)
	skynet.error(string.format("    account login_session: %d verify secret", login_session))

	local t = saved_session[login_session] or error (string.format("login_session: %d invalid or expire ", login_session))

	local text = aes.decrypt (secret, t.key) or error (string.format("login_session: %d secret decrypt failed", login_session))
	assert (text == t.token, 
		string.format("account login_session: %d verify token failed", login_session))
	t.token = nil

	return t.account_id
end

skynet.start (function ()
	skynet.dispatch ("lua", function (_, _, command, ...)
		local function pret (ok, ...)
			if not ok then 
				syslog.warningf (...)
				skynet.ret ()
			else
				skynet.retpack (...)
			end
		end

		local f = assert (CMD[command])
		pret (xpcall (f, traceback, ...))
	end)
end)

