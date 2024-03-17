local skynet = require "skynet"
local socket = require "skynet.socket"
local proxy = require "socket_proxy"
local log = require "log"
local service = require "service"

local hub = {}
local data = { socket = {} }

local function auth_socket(fd, addr)
	return skynet.call(service.loginserver, "lua", "shakehand" , fd, addr)
end

local function assign_agent(fd, account_id)
	skynet.call(service.manager, "lua", "assign", fd, account_id)
end

local function new_socket(fd, addr)
	data.socket[fd] = "[AUTH]"
	proxy.subscribe(fd)
	local ok , account_id = pcall(auth_socket, fd, addr)
	if not ok then
		log("Auth faild %d(%s), error: %s", fd, addr, tostring(account_id))
		proxy.close(fd)
		return
	end
	if not account_id then
		log("Auth faild %d(%s)", fd, addr)
		proxy.close(fd)
		data.socket[fd] = nil
		return
	end
	data.socket[fd] = account_id
	if not pcall(assign_agent, fd, account_id) then
		log("Assign failed %d(%s) to %s", fd, addr, account_id)
		proxy.close(fd)
		data.socket[fd] = nil
		return
	end
	-- success
end

function hub.open(conf)
	local ip = conf.ip or "0.0.0.0"
	local port = assert(conf.port)
	log("Listen %s:%d", ip, port)
	assert(data.fd == nil, "Already open")
	data.fd = socket.listen(ip, port)
	data.ip = ip
	data.port = port
	socket.start(data.fd, new_socket)
end

function hub.close()
	assert(data.fd)
	log("Close %s:%d", data.ip, data.port)
	socket.close(data.fd)
	data.ip = nil
	data.port = nil
end

service.init {
	command = hub,
	info = data,
	require = {
		"loginserver",
		"manager",
	}
}
