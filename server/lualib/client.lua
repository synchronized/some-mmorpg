local skynet = require "skynet"
local crypt = require "skynet.crypt"

local errcode= require "errcode.errcode"
local proxy = require "socket_proxy"
--local protoloader = require "proto/sproto_mgr"
local protobuf = require "proto/pb_mgr"
local log = require "log"
local cjsonutil = require "cjson.util"

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
	proxy.write(fd, msg, sz)
end

function client.read( fd )
	proxy.subscribe(fd)
	return skynet.tostring(proxy.read(fd))
end

function client.write( fd, luastring)
	proxy.write(fd, skynet.pack(luastring))
end

local emptytable = {}
function client.dispatch_message( c )
	local fd = c.fd
	proxy.subscribe(fd)
	while true do
		local msg, sz = proxy.read(fd)
		local type, session_id, args, fnresponse = host:dispatch(msg, sz)
		if c.exit then
			return c
		end
		if type == "REQUEST" then
			local typename = session_id
			local f = c.REQUEST and c.REQUEST[typename] or handler[typename] -- session_id is request type
			if not f then
				-- unsupported command, disconnected
				error(string.format("request %s have no handler", typename))
			else
				-- f may block , so fork and run
				skynet.fork(function()
					local ok, err, resp = xpcall(f, traceback, c, args)
					log("=============typename: %s, ok:%s, err:%s, resp:%s", typename, tostring(ok), tostring(err), tostring(resp))
					if not ok then
						log.printf("<error> response error = %s", err)
						if fnresponse then
							proxy.write(fd, fnresponse(emptytable, {
								ok = false,
								error_code = errcode.COMMON_SERVER_ERROR,
							}))
						end
					elseif err ~= nil and err ~= errcode.SUCCESS  then
						if fnresponse then
							proxy.write(fd, fnresponse(resp or emptytable, {error_code = err}))
						end
					else
						if fnresponse then
							proxy.write(fd, fnresponse(resp or emptytable))
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

function client.dispatch( c )
	local fd = c.fd
	proxy.subscribe(fd)
	while true do
		local msg, sz = proxy.read(fd)
		if c.exit then
			return c
		end
		local bytemsg = skynet.tostring(msg, sz)
		local bytes_header, n = string.unpack(">s2", bytemsg)
		bytemsg = string.sub(bytemsg, n)
		local bytes_body, _ = string.unpack(">s2", bytemsg)

		local msg_header = assert(protobuf.decode('proto.req_msgheader', bytes_header))
		local msgname = msg_header.msg_name
		local client_session_id = msg_header.session
		local args = nil
		if #bytes_body > 0 then
			args = assert(protobuf.decode('proto.'..msgname, bytes_body))
		end

		local f = c.REQUEST and c.REQUEST[msgname] or handler[msgname] -- session_id is request type
		if not f then
			-- unsupported command, disconnected
			error(string.format("request %s have no handler", msgname))
		else
			-- f may block , so fork and run
			skynet.fork(function()
				local ok, err, error_code = xpcall(f, traceback, c, args)
				--log("=============msgname: %s, ok:%s, err:%s, error_code:%s", msgname, tostring(ok), tostring(err), tostring(error_code))
				local msgresult = nil
				if not ok then
					log.printf("<error> response error = %s", err)
					if client_session_id > 0 then
						msgresult = {
							session = client_session_id,
							result = false,
							error_code = errcode.COMMON_SERVER_ERROR,
						}
					end
				elseif error_code ~= nil then
					if client_session_id > 0 then
						msgresult = {
							session = client_session_id,
							result = err,
							error_code = error_code,
						}
					end
				elseif type(err) == "number" then
					if client_session_id > 0 then
						msgresult = {
							session = client_session_id,
							result = err == errcode.SUCCESS,
							error_code = err,
						}
					end
				elseif type(err) == "boolean" then
					if client_session_id > 0 then
						msgresult = {
							session = client_session_id,
							result = err,
							error_code = errcode.SUCCESS,
						}
					end
				else
					--error()
				end
				if msgresult ~= nil then
					client.sendmsg(c, 'res_msgresult', msgresult)
				end
			end)
		end
	end
end

function client.close(fd)
	proxy.close(fd)
end

function client.sendmsg(c, t, data)
	proxy.subscribe(c.fd)
	local bytes_header = assert(protobuf.encode("proto.res_msgheader", {
											  msg_name = t,
	}))
	--log("=============sendmsg: %s, data:%s", t, cjsonutil.serialise_value(data))
	local bytes_body = ""
	if data then
		bytes_body = assert(protobuf.encode('proto.'..t, data))
		--log("=============sendmsg: %s, bytes_body:%s|", t, crypt.base64encode(bytes_body))
	end


	local msg = string.pack(">s2>s2", bytes_header, bytes_body)

	--log("=============sendmsg: %s, hexdata:%s", t, crypt.base64encode(msg))

	proxy.write(c.fd, msg)
end

function client.init(name)
	return function ()
		--local protod = skynet.uniqueservice "protod"
		--local protoindex = assert(skynet.call(protod, "lua", "loadindex", name))
		--host, sender = protoloader.loadbyserver (protoindex)
	end
end

return client
