local socket = require "simplesocket"
local sproto = require "sproto"
local protoloader = require "protoloader"

local cjsonutil = require "cjson.util"

local message = {}
local var = {
	session_id = 0 ,
	session = {},
	object = {},
}

function message.register(server_proto)
	local index = protoloader.getindexbyname(server_proto)
	var.host, var.request = protoloader.loadbyclient(index)
end

function message.peer(addr, port)
	var.addr = addr
	var.port = port
end

function message.isconnect()
	return socket.isconnect()
end

function message.connect()
	socket.connect(var.addr, var.port)
	socket.isconnect()
end

function message.disconnect()
	socket.close()
end

function message.bind(obj, handler)
	var.object[obj] = handler
end

function message.request(name, args)
	var.session_id = var.session_id + 1
	var.session[var.session_id] = { name = name, req = args }
	socket.write(var.request(name , args, var.session_id))

	if name ~= "ping" then
		print(string.format("==> REQUEST %s(%d) data: %s", 
			name, var.session_id, cjsonutil.serialise_value(args)))
	end
	return var.session_id
end

function message.dispatch_message(ti)
	local msg = socket.read(ti)
	if not msg then
		return false
	end
	local t, session_id, resp, ret = var.host:dispatch(msg)
	if t == "REQUEST" then
		for obj, handler in pairs(var.object) do
			local f = handler[session_id]	-- session_id is request type
			if f then
				local ok, err_msg = pcall(f, obj, resp)	-- resp is content of push
				if not ok then
					print(string.format("push %s for [%s] error : %s", session_id, tostring(obj), err_msg))
				end
			end
		end
	else
		local session = var.session[session_id]
		var.session[session_id] = nil
		if session.name ~= "ping" then
			print(string.format("<== RESPONSE %s(%d) ret: %s data: %s", 
				session.name, session_id, 
				cjsonutil.serialise_value(ret), cjsonutil.serialise_value(resp)))
		end

		for obj, handler in pairs(var.object) do
			local f = handler[session.name]
			if f then
				local ok, err_msg = pcall(f, obj, session.req, resp, ret)
				if not ok then
					print(string.format("    session %s[%d] for [%s] error : %s", session.name, session_id, tostring(obj), err_msg))
				end
			else
				print(string.format("    session %s[%d] for [%s] have no handler", session.name, session_id, tostring(obj)))
			end
		end
	end

	return true
end

function message.update(ti)
	message.dispatch_message(ti)
end

return message
