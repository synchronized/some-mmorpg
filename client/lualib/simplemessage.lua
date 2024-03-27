local socket = require "simplesocket"
local crypt = require "client.crypt"
--local protoloader = require "proto/sproto_mgr"
local protobuf = require "proto/pb_mgr"

local cjsonutil = require "cjson.util"

local message = {}
local var = {
	session_id = 0 ,
	session = {},
	object = {},
}

function message.register(server_proto)
	--local index = protoloader.getindexbyname(server_proto)
	--var.host, var.request = protoloader.loadbyclient(index)
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

function message.read(ti)
  return socket.read(ti)
end

function message.write(msg)
  socket.write(msg)
end

function message.sendmsg(name, args, callback)
	var.session_id = var.session_id + 1
	var.session[var.session_id] = { name = name, req = args, callback = callback}

	local bytes_header = assert(protobuf.encode("proto.req_msgheader", {
		msg_name = name,
		session = var.session_id,
	}))
	local bytes_body = ""
	if args then
		bytes_body = assert(protobuf.encode('proto.'..name, args))
	end
	local msg = string.pack(">s2", bytes_header)..string.pack(">s2", bytes_body)

	socket.write(msg)

	return var.session_id
end

function message.dispatch_pb(ti)
	local msg = socket.read(ti)
	if not msg then
		return false
	end
	local bytemsg = msg

	local bytes_header, bytes_body = string.unpack(">s2>s2", bytemsg)

	local msg_header = assert(protobuf.decode('proto.res_msgheader', bytes_header))

	local msgname = msg_header.msg_name
	local resp = nil
	if #bytes_body > 0 then
		resp = assert(protobuf.decode('proto.'..msgname, bytes_body))
	end

	if msgname == "res_msgresult" then
		if resp then
			local client_session_id = resp.session
			local session = var.session[client_session_id]
			var.session[msgname] = nil
			if session ~= nil then
				if session.callback ~= nil then
					local ok, err_msg = pcall(session.callback, session.req, resp.result, resp.error_code)
					if not ok then
						print(string.format("    session %s[%d] for msgresult error : %s", session.name, client_session_id, tostring(err_msg)))
					end
				end
			end
		else
			print(string.format("    session %s resp is nil", msgname))
		end
	else
		if msgname ~= "ping" then
			print(string.format("<== RESPONSE %s data: %s", msgname, cjsonutil.serialise_value(resp)))
		end
		for obj, handler in pairs(var.object) do
			local f = handler[msgname]
			if f then
				local ok, err_msg = pcall(f, obj, resp)
				if not ok then
					print(string.format("    session %s for [%s] error : %s", tostring(msgname), tostring(obj), tostring(err_msg)))
				end
			else
				print(string.format("    session %s for [%s] have no handler", tostring(msgname), tostring(obj)))
			end
		end
	end

	return true
end

function message.dispatch_message(ti)
	local msg = socket.read(ti)
	if not msg then
		return false
	end
	local t, session_id, resp, ret = var.host:dispatch(msg)
	if t == "REQUEST" then
		if session_id ~= "ping" then
			print(string.format("<== REQUEST %s data: %s", session_id, cjsonutil.serialise_value(resp)))
		end

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
	message.dispatch_pb(ti)
end

return message
