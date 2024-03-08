local skynet = require "skynet"

local protoloader = require "protoloader"
local srp = require "srp"
local aes = require "aes"
local uuid = require "uuid"

local service = require "service"
local client = require "client"
local log = require "log"

local errcode = require "errcode.errcode"

local mainserver
local database
local auth_timeout
local session_expire_time
local session_expire_time_in_second
local connection = {}
local saved_session = {}

local function close (fd)
	if connection[fd] then
		client.close (fd)
		connection[fd] = nil
	end
end

local function read_msg (fd)
	return pcall(client.readmessage, fd)
end

local function send_msg (fd, msg, sz)
	client.writemessage (fd, msg, sz)
end

local empty_response = {}

local function reterrcode(fd, response, error_code)
	send_msg (fd, response( empty_response, { error_code = error_code, }))
end

local loginwork = {}

-- call by loginserver
function loginwork.init (main, id, conf)
	mainserver = main
	database = skynet.uniqueservice ("database")

	auth_timeout = conf.auth_timeout * 100
	session_expire_time = conf.session_expire_time * 100
	session_expire_time_in_second = conf.session_expire_time
end

-- call by loginserver
local function auth (fd, addr)
	connection[fd] = addr
	skynet.timeout (auth_timeout, function ()
		if connection[fd] == addr then
			log ("connection %d from %s auth timeout!", fd, addr)
			close (fd)
		end
	end)

	local ok, type, name, args, response = read_msg (fd)
	if not ok then
		log ("read message failed err: %s", tostring(type))
		close()
		return
	end
	if type ~= "REQUEST" then
		log ("handler message type is not 'REQUEST'")
		return
	end

	if name == "handshake" then
		-- handshake
		if not args then
			reterrcode(fd, response, errcode.COMMON_INVALID_REQUEST_PARMS) --请求参数有误
			return
		end
		if not args.username then
			reterrcode(fd, response, errcode.LOGIN_INVALID_USERNAME)
			return
		end
		if not args.client_pub then
			reterrcode(fd, response, errcode.LOGIN_INVALID_CLIENT_PUB)
			return
		end
		local username = args.username
		log ( "<login> handshake username: %s", username)

		local account = assert(skynet.call (database, "lua", "account", "load", username),
			string.format("load account username: %s failed", username))

		local session_key, _, pkey = srp.create_server_session_key (account.verifier, args.client_pub)
		local challenge = srp.random ()

		send_msg (fd, response( {
			user_exists = (account.account_id ~= nil),
			salt = account.salt,
			server_pub = pkey,
			challenge = challenge,
		}))

		-- auth
		ok, type, name, args, response = read_msg (fd)
		if not ok then
			log ("read message failed err: %s", tostring(type))
			return
		end
		if type ~= "REQUEST" then
			log ("handler message type is not 'REQUEST'")
			return
		end
		if name ~= "auth" then
			log ("handler message name is not 'auth'")
			return
		end
		if not args then
			reterrcode(fd, response, errcode.COMMON_INVALID_REQUEST_PARMS) --请求参数有误
			return
		end
		if not args.challenge then
			reterrcode(fd, response, errcode.LOGIN_INVALID_CHALLENGE) --challenge 有误
			return
		end

		local text = aes.decrypt (args.challenge, session_key)
		if challenge ~= text then
			reterrcode(fd, response, errcode.LOGIN_CHALLENGE_VERIFY_FAILED) --challenge 验证失败
			return
		end

		log ("<login> auth username: %s", username)

		local account_id = tonumber (account.account_id)
		if not account_id then
			assert (args.password)
			account_id = uuid.gen ()
			local password = aes.decrypt (args.password, session_key)
			account.account_id = assert(skynet.call (database, "lua", "account", "create", account_id, username, password),
				string.format ("create account %s/%d failed", username, account_id))

			log ("    account username: %s account_id: %d create", username, account_id)
		else
			log ("    account username: %s account_id: %d login", username, account_id)
		end

		challenge = srp.random ()
		local login_session = skynet.call (mainserver, "lua", "save_session", account_id, session_key, challenge)

		log ("    account username: %s account_id: %d login_session: %d",
			username, account_id, login_session)

		send_msg (fd, response ({
			login_session = login_session,
			expire = session_expire_time_in_second,
			challenge = challenge,
		}))

		ok, type, name, args, response = read_msg (fd)
		if not ok then
			log ("read message failed err: %s", tostring(type))
			return
		end
		if type ~= "REQUEST" then
			log ("handler message type is not 'REQUEST'")
			return
		end
	end

	-- challenge
	if name ~= "challenge" then
		log ("handler message name is not 'auth'")
		return
	end
	if not args then
		reterrcode(fd, response, errcode.COMMON_INVALID_REQUEST_PARMS) --请求参数有误
		return
	end
	if not args.login_session then
		reterrcode(fd, response, errcode.LOGIN_INVALID_SESSION_ID) -- session_id 有误
		return
	end
	if not args.challenge then
		reterrcode(fd, response, errcode.errcode.LOGIN_INVALID_CHALLENGE) --challenge 有误
		return
	end

	local token, challenge = skynet.call (mainserver, "lua", "challenge", args.login_session, args.challenge)
	if not token  or not challenge then
		reterrcode(fd, response, errcode.LOGIN_SESSION_TIMEOUT) --会话超时
		return
	end

	send_msg (fd, response ({
		token = token,
		challenge = challenge,
	}))

	connection[fd] = nil

	return skynet.call (mainserver, "lua", "get_account_id", args.login_session)
end

function loginwork.auth(fd, addr)
	local account_id = auth(fd, addr)
	if not account_id then
		close(fd)
		return
	end
	return account_id
end

-- call by loginserver
function loginwork.save_session (login_session, account_id, session_key, challenge)
	log ("    account account_id: %d, login_session: %d savesession ",
		account_id, login_session)

	saved_session[login_session] = {
		account_id = account_id,
		key = session_key,
		challenge = challenge,
	}
	skynet.timeout (session_expire_time, function ()
		local t = saved_session[login_session]
		if t then
			if t and t.key == session_key then
				saved_session[login_session] = nil
			end
		end
	end)
end

-- call by loginserver
function loginwork.challenge (login_session, secret)
	log ("    account login_session: %d verify challenge secret", login_session)

	local t = saved_session[login_session]
	if not t then
		return
	end

	local text = aes.decrypt (secret, t.key) or error ()
	assert (text == t.challenge)

	t.token = srp.random ()
	t.challenge = srp.random ()

	return t.token, t.challenge
end

-- call by loginserver
function loginwork.verify (login_session, secret)
	log ("    account login_session: %d verify secret", login_session)

	local t = saved_session[login_session]
	if not t then
		return
	end

	local text = aes.decrypt (secret, t.key) or error (string.format("login_session: %d secret decrypt failed", login_session))
	assert (text == t.token,
		string.format("account login_session: %d verify token failed", login_session))
	t.token = nil

	return t.account_id
end

function loginwork.get_account_id (login_session)
	local t = saved_session[login_session]
	if not t then
		return
	end

	return t.account_id
end

service.init {
	command = loginwork,
	--info = users,
	init = client.init (protoloader.LOGIN),
}
