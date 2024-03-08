local skynet = require "skynet"
local errcode= require "errcode.errcode"

local proxy = require "socket_proxy"
local protoloader = require "protoloader"
local log = require "log"

local traceback = debug.traceback

local client = {}
local host
local sender
local handler = {}

local var = {
	session_id = 0 ,
	session = {},
	object = {},
}

function client.handler()
	return handler
end

function client.readmessage( fd )
	proxy.subscribe(fd)
	local msg, sz = proxy.read(fd)
	return host:dispatch(msg, sz)
end

function client.writemessage( fd, msg, sz )
	proxy.write(fd,  msg, sz)
end


local emptytable = {}
function client.dispatch( c )
	local fd = c.fd
	proxy.subscribe(fd)
	while true do
		local msg, sz = proxy.read(fd)
		local type, session_id, args, fnresponse = host:dispatch(msg, sz)
		if type == "REQUEST" then
			if c.exit then
				return c
			end
			local typename = session_id
			local f = c.REQUEST and c.REQUEST[typename] or handler[typename] -- session_id is request type
			if not f then
				-- unsupported command, disconnected
				error(string.format("request %s have no handler", typename))
			else
				-- f may block , so fork and run
				skynet.fork(function()
					local ok, result, resp = xpcall(f, traceback, c, args)
					if not ok then
						log.printf("<error> response error = %s", result)
						if fnresponse then
							proxy.write(fd, fnresponse(emptytable, {
								ok = false,
								error_code = errcode.COMMON_SERVER_ERROR,
							}))
						end
					else
						if fnresponse then
							proxy.write(fd, fnresponse(resp or emptytable, result))
						end
					end
				end)
			end
		else
			local session = assert(var.session[session_id], string.format("invalid push session id: %d", session_id))
			var.session[session_id] = nil

			local f = c.RESPONSE and c.RESPONSE[session.name] or handler[session.name]
			if not f then
				-- unsupported response, disconnected
				error(string.format("session %s[%d] have no handler", session.name, session_id))
			else
				-- f may block , so fork and run
				skynet.fork(function()
					local ok, err = xpcall(f, traceback, c, session.req, args)
					if not ok then
						error(string.format("    session %s[%d] for [%s] error : %s", session.name, session_id, tostring(err)))
					end
				end)
			end
		end
	end
end

function client.close(fd)
	proxy.close(fd)
end

-- 向客户端推送消息
function client.push(c, t, data)
	proxy.write(c.fd, sender(t, data))
end

-- 向客户端发送请求消息
function client.request(c, t, data)
	var.session_id = var.session_id + 1
	proxy.write(c.fd, sender(t, data, var.session_id))
	var.session[var.session_id] = {
		name = t,
		req = data,
	}
end

function client.init(name)
	return function ()
		local protod = skynet.uniqueservice "protod"
		local protoindex = assert(skynet.call(protod, "lua", "loadindex", name))
		host, sender = protoloader.loadbyserver (protoindex)
	end
end

return client
