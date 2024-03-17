local skynet = require "skynet"

local service = require "service"
local log = require "log"

local works = {}

local data = {
	session_id = 1,
	balance = 1,
	nwork = 0,
}

local users = {}

local loginserver = {}

function loginserver.open (conf)
	for i = 1, conf.nwork or 8 do
		local s = skynet.newservice ("loginwork")
		skynet.call (s, "lua", "init", skynet.self (), i, conf)
		table.insert (works, s)
	end
	data.nwork = #works
end

local function getnextworkindex()
	local result = data.balance
	data.balance = data.balance + 1
	if data.balance > data.nwork then data.balance = 1 end
	return result
end

function loginserver.shakehand(fd, addr)
	log ("shakehand fd:%d", fd)

	local s = works[getnextworkindex()]

	return skynet.call (s, "lua", "auth", fd, addr)
end

local function getnextlogin_session()
	local login_session = data.session_id
	data.session_id = data.session_id + 1
	return login_session
end

function loginserver.save_session (account_id, session_key, challenge)
	local login_session = getnextlogin_session()

	local s = works[(login_session % data.nwork) + 1]
	skynet.call (s, "lua", "save_session", login_session, account_id, session_key, challenge)
	return login_session
end

function loginserver.verify (login_session, token)
	local s = works[(login_session % data.nwork) + 1]
	return skynet.call (s, "lua", "verify", login_session, token)
end

function loginserver.get_account_id (login_session)
	local s = works[(login_session % data.nwork) + 1]
	return skynet.call (s, "lua", "get_account_id", login_session)
end

service.init {
	command = loginserver,
	info = users,
}
