
package.path = table.concat({
	"client/?.lua",
	"client/lualib/?.lua",
	"common/?.lua",
	"3rd/skynet/lualib/?.lua",
}, ";")
package.cpath = table.concat({
	"client/luaclib/?.so",
	"server/luaclib/?.so",
	"3rd/skynet/luaclib/?.so",
	package.cpath,
}, ";")

print("package.path:"..package.path)
local cjsonutil = require "cjson.util"
local socket = require "client.socket"
local srp = require "srp"
local aes = require "aes"
local protoloader = require "protoloader"
local constant = require "constant"

protoloader.init()

local user = { username = arg[1], password = arg[2] }

do
	if not user.username then
		print([[Usage:
	lua client/client.lua <username> <password>
]])
		return
	end

	if not user.password then
		user.password = constant.default_password
	end
end



local loginserver = {
	addr = "127.0.0.1",
	port = 9777,
	servername = "loginserver",
}
local gameserver = {
	addr = "127.0.0.1",
	port = 9555,
	servername = "gameserver",
}

----------------------------------------------------------
-- common func
----------------------------------------------------------

local function comm_recv_pack(f)
	local function try_recv(fd, last)
		local result
		result, last = f(last)
		if result then
			return result, last
		end
		local r = socket.recv(fd)
		if not r then
			return nil, last
		end
		if r == "" then
			error (string.format ("socket %d closed", fd))
		end
		return f(last .. r)
	end

	return function(fd, last)
		return try_recv(fd, last)
	end
end

local function comm_unpack_package (text)
	local size = #text
	if size < 2 then
		return nil, text
	end
	local s = text:byte (1) * 256 + text:byte (2)
	if size < s + 2 then
		return nil, text
	end

	return text:sub (3, 2 + s), text:sub (3 + s)
end


----------------------------------------------------------
-- server manager
----------------------------------------------------------
local server_mgr = {}

function server_mgr:new(conf, server_proto, cli_mgr)
	self.__index = self

	local proto_host, proto_request = protoloader.loadbyclient(protoloader.getindexbyname(server_proto))

	local obj = setmetatable({
		cli_mgr = cli_mgr,
		conf = {
			addr = assert(conf.addr),
			port = assert(conf.port),
			servername = assert(conf.servername),
		},

		proto_host = assert(proto_host),
		proto_request = assert(proto_request),

		last_recv_data = "",
		recv_handler = comm_recv_pack(comm_unpack_package),
	}, self)
	
	if cli_mgr.on_server_create then
		cli_mgr:on_server_create(obj)
	end
	return obj
end

function server_mgr:close()
	if self.fd then
		socket.close(self.fd)
	end
	self.cli_mgr = nil
	self.conf = nil
end

function server_mgr:open()
	self.fd = assert (socket.connect (self.conf.addr, self.conf.port))
	print (string.format ("%s server connected(%s:%d), fd = %d", 
		self.conf.servername, self.conf.addr, self.conf.port, self.fd))
end

function server_mgr:send_message (msg)
	local package = string.pack (">s2", msg)
	socket.send (self.fd, package)
end

function server_mgr:send_request(pkgname, args)
	local session_id = self.cli_mgr:get_session_id()
	print (string.format("==> send_request pkgname: %s session_id: %d request: %s", 
		pkgname, session_id, cjsonutil.serialise_value(args)))
	
	local str = self.proto_request(pkgname, args, session_id)
	self:send_message(str)
	self.cli_mgr:set_session(session_id, { pkgname = pkgname, args = args })
end

function server_mgr:recv_message ()
	
	local v
	v, self.last_recv_data = self.recv_handler(self.fd, self.last_recv_data)
	if not v then
		return false
	end
	return true, self.proto_host:dispatch (v)
end

----------------------------------------------------------
-- client manager
----------------------------------------------------------

local client_mgr = {
	session_map = {},
	session_currid = 0,

	curr_server_mgr = nil, -- 当前服务器管理器
}

function client_mgr:get_session_id()
	self.session_currid = self.session_currid + 1
	return self.session_currid
end

function client_mgr:set_session(session_id, data)
	self.session_map[session_id] = data
end

function client_mgr:get_session(session_id)
	return self.session_map[session_id]
end

function client_mgr:on_server_create(curr_server_mgr)
	if self.curr_server_mgr then
		self.curr_server_mgr:close()
	end
	self.curr_server_mgr = curr_server_mgr
end

function client_mgr:send_request(pkgname, args)
	local cur_server_mgr = assert(self.curr_server_mgr)
	cur_server_mgr:send_request(pkgname, args)
end

function client_mgr:dispatch_message()
	while true do
		local cur_server_mgr = assert(self.curr_server_mgr)
		if not self:handle_message (cur_server_mgr:recv_message()) then
			break
		end
	end
end

local rr = { wantmore = true }

function client_mgr:handle_request (pkgname, args, response)
	print ("request pkgname: "..pkgname..cjsonutil.serialise_value(args))

	if pkgname:sub (1, 3) == "aoi" and  pkgname ~= "aoi_remove" then
		if response then
			local cur_server_mgr = assert(self.curr_server_mgr)
			cur_server_mgr:send_message (response (rr))
		end
	end
end

local RESPONSE = {}

function RESPONSE:handshake (args)
	local username = user.username
	print (string.format("<== RESPONSE.handshake username:%s", username))

	if args.user_exists then
		local key = srp.create_client_session_key (username, user.password, args.salt, user.private_key, user.public_key, args.server_pub)
		user.session_key = key
		local ret = { 
			challenge = aes.encrypt (args.challenge, key),
		}
		client_mgr:send_request ("auth", ret)
	else
		local key = srp.create_client_session_key (username, user.password, args.salt, user.private_key, user.public_key, args.server_pub)
		user.session_key = key
		local ret = { 
			challenge = aes.encrypt (args.challenge, key), 
			password = aes.encrypt (user.password, key),
		}
		client_mgr:send_request ("auth", ret)
	end
end

function RESPONSE:auth (args)
	user.login_session = args.login_session
	local challenge = aes.encrypt (args.challenge, user.session_key)
	client_mgr:send_request ("challenge", { 
		login_session = args.login_session, 
		challenge = challenge,
	})
end

function RESPONSE:challenge (args)
	local token = aes.encrypt (args.token, user.session_key)

	local gameserver_mgr = server_mgr:new(gameserver, protoloader.GAME, client_mgr)
	gameserver_mgr:open()

	client_mgr:send_request ("login", { 
		login_session = user.login_session, 
		token = token,
	})
end

function RESPONSE:login (args)
	if not args.success then
		error (string.format("<== login failed username:%s", user.username))
	end
	client_mgr:send_request ("character_list")
end

function RESPONSE:character_list (args)
end

function client_mgr:handle_response (session_id, args)
	local session_data = self:get_session(session_id)
	if not session_data then
		error(string.format("invalid session_id: %d", session_id))
	end
	self:set_session(session_id, nil)
	local pkgname = session_data.pkgname
	local f = RESPONSE[pkgname]
	
	print (string.format("<== handle_response pkgname: %s, session_id: %d, response: %s", 
		pkgname, session_id, cjsonutil.serialise_value(args)))
	if f then
		f (session_data.args, args)
	else
		print(string.format("    response handle not found"))
	end
end

function client_mgr:handle_message (ok, t, ...)
	if not ok then
		return false
	end
	if t == "REQUEST" then
		self:handle_request (...)
	else
		self:handle_response (...)
	end
	return true
end

function client_mgr:request_shakehand()
	local private_key, public_key = srp.create_client_key ()
	user.private_key = private_key
	user.public_key = public_key
	self:send_request ("handshake", { username = user.username, client_pub = public_key })
end

local HELP = {}

function HELP.character_create ()
	return [[
	name: your nickname in game
	race: 1(human)/2(orc)
	class: 1(warrior)/2(mage)
]]
end

function client_mgr:handle_cmd(line)
	local cmd
	local p = string.gsub (line, "([%w-_]+)", function (s)
		cmd = s
		return ""
	end, 1)

	if string.lower (cmd) == "help" then
		for k, v in pairs (HELP) do
			print (string.format ("command:\n\t%s\nparameter:\n%s", k, v()))
		end
		return
	end

	local t = {}
	local f, err = load (p, "=(load)" , "t", t)

	if not f then error (err) end
	f ()

	print (string.format("<cmd> cmd: %s, params: %s", tostring(cmd), cjsonutil.serialise_value(t)))

	if not next (t) then t = nil end

	if cmd then
		local ok, err = pcall (self.send_request, self, cmd, t)
		if not ok then
			print (string.format ("    invalid command (%s), error (%s)", cmd, err))
		end
	end
end

function client_mgr:event_loop()
	print ('type "help" to see all available command.')
	while true do
		client_mgr:dispatch_message ()
		local cmd = socket.readstdin ()
		if cmd then
			self:handle_cmd(cmd)
		else
			socket.usleep (100)
		end
	end
end


local loginserver_mgr = server_mgr:new(loginserver, protoloader.LOGIN, client_mgr)

-- 连接登录服务器
loginserver_mgr:open()

-- 发送第一个握手包
client_mgr:request_shakehand()

-- 开启事件循环
client_mgr:event_loop()

