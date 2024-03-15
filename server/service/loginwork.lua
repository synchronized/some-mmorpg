local skynet = require "skynet"
local crypt = require "skynet.crypt"

local protoloader = require "protoloader"
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

local function retdata(fd, response, resp)
	send_msg (fd, response( resp))
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

	--- new
	local user = {
		fd = fd,
	}

	-- acknowledgment
	local acknumber = crypt.randomkey()
	client.push(user, "acknowledgment", {
					acknumber = acknumber,
	})

	-- handshake
	local ok, type, name, args, response = read_msg(fd)
	if not ok then
		log ("read message failed err: %s", tostring(type))
		close()
		return
	end
	if type ~= "REQUEST" then
		log ("handler message type is not 'REQUEST' type:%s", tostring(type))
		close()
		return
	end
	if name ~= "handshake" then
		log ("handler message name is not 'handshake' name:%s", tostring(name))
		close()
		return
	end
	if not args then
		reterrcode(fd, response, errcode.COMMON_INVALID_REQUEST_PARMS) --请求参数有误
		close()
		return
	end
	if not args.client_pub then
		reterrcode(fd, response, errcode.LOGIN_INVALID_CLIENT_PUB)
		close()
		return
	end

	local clientkey = args.client_pub
	if #clientkey ~= 8 then
		reterrcode(fd, response, errcode.LOGIN_INVALID_CLIENT_PUB)
		close()
		return
	end
	local serverkey = crypt.randomkey()
	retdata(fd, response, {
				secret = crypt.dhexchange(serverkey),
	})
	local secret = crypt.dhsecret(clientkey, serverkey)

	-- challenge
	ok, type, name, args, response = read_msg(fd)
	if not ok then
		log ("read message failed err: %s", tostring(type))
		close()
		return
	end
	if type ~= "REQUEST" then
		log ("handler message type is not 'REQUEST'")
		close()
		return
	end
	if name ~= "challenge" then
		log ("handler message name is not 'handshake' name:%s", tostring(name))
		close()
		return
	end
	if not args then
		reterrcode(fd, response, errcode.COMMON_INVALID_REQUEST_PARMS) --请求参数有误
		close()
		return
	end
	if not args.hmac then
		reterrcode(fd, response, errcode.LOGIN_INVALID_HMAC)
		close()
		return
	end

	local hmac = crypt.hmac64(acknumber, secret)
	if hmac ~= args.hmac then
		reterrcode(fd, response, errcode.LOGIN_INVALID_HMAC)
		close()
		return
	end
	retdata(fd, response, empty_response)

	--auth
	ok, type, name, args, response = read_msg(fd)
	if not ok then
		log ("read message failed err: %s", tostring(type))
		close()
		return
	end
	if type ~= "REQUEST" then
		log ("handler message type is not 'REQUEST'")
		close()
		return
	end
	if name ~= "auth" then
		log ("handler message name is not 'auth' name:%s", tostring(name))
		close()
		return
	end
	if not args then
		reterrcode(fd, response, errcode.COMMON_INVALID_REQUEST_PARMS) --请求参数有误
		close()
		return
	end
	if not args.username then
		reterrcode(fd, response, errcode.LOGIN_INVALID_USERNAME)
		close()
		return
	end
	if not args.password then
		reterrcode(fd, response, errcode.LOGIN_INVALID_PASSWORD)
		close()
		return
	end
	local username = crypt.desdecode(secret, args.username)
	local password = crypt.desdecode(secret, args.password)

	log ("<login> auth username: %s, password: %d", username, password)

	local account = assert(skynet.call (database, "lua", "account", "load", username),
							string.format("load account username: %s failed", username))

	local account_id = tonumber (account.account_id)

	if not account_id then
		account_id = uuid.gen ()
		account.account_id = assert(skynet.call (database, "lua", "account", "create",
													account_id, username, password),
			string.format ("create account %s/%d failed", username, account_id))

		log ("    account username: %s account_id: %d create", username, account_id)
	else
		if password ~= account.password then
			reterrcode(fd, response, errcode.LOGIN_INVALID_USERNAME_OR_PASSWORD)
			close()
			return
		end
		log ("    account username: %s account_id: %d login", username, account_id)
	end

	local token = crypt.randomkey()
	local login_session = skynet.call (mainserver, "lua", "save_session", account_id, clientkey, token)

	retdata(fd, response, {
				login_session = login_session,
				expire = session_expire_time_in_second,
				token = token,
	})

	connection[fd] = nil
	return account_id
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
function loginwork.save_session (login_session, account_id, client_key, token)
	log ("    account account_id: %d, login_session: %d savesession ",
		account_id, login_session)

	saved_session[login_session] = {
		account_id = account_id,
		key = client_key,
		token = token,
	}
	skynet.timeout (session_expire_time, function ()
		local t = saved_session[login_session]
		if t then
			if t and t.key == client_key then
				saved_session[login_session] = nil
			end
		end
	end)
end

-- call by loginserver
function loginwork.verify (login_session, secret)
	log ("    account login_session: %d verify secret", login_session)

	local t = saved_session[login_session]
	if not t then
		return
	end

	local text = crypt.decrypt (t.key, secret) or error (string.format("login_session: %d secret decrypt failed", login_session))
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
