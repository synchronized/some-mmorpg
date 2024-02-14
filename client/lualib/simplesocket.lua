local lsocket = require "lsocket"

local socket = {}
local fd
local message

socket.error = setmetatable({}, { __tostring = function() return "[socket error]" end } )

function socket.connect(addr, port)
	assert(fd == nil)
	local err
	fd, err = lsocket.connect(addr, port)
	if fd == nil then
		error(debug.traceback(err, 3))
	end

	lsocket.select(nil, {fd})
	local ok, errmsg = fd:status()
	if not ok then
		error(debug.traceback(errmsg, 3))
	end

	message = ""
end

function socket.isconnect(ti)
	if not fd then
		return false
	end
	local rd, wt = lsocket.select(nil, { fd }, ti)
	local ok, errmsg = fd:status()
	if not ok then
		error(debug.traceback(errmsg, 3))
	end
	return next(wt) ~= nil
end

function socket.close()
	if fd then
		fd:close()	
	end
	fd = nil
	message = nil
end

function socket.read(ti)
	while true do
		local ok, msg, n = pcall(string.unpack, ">s2", message)
		if not ok then
			local rd = lsocket.select({fd}, ti)
			if not rd then
				return nil
			end
			if next(rd) == nil then
				return nil
			end
			local p, err = fd:recv()
			if not p then
				if err then
					print("err"..err)
					error(debug.traceback(err, 3))
				end
				print("<error> socket close by peer")
				socket.close()
				return nil
			end
			message = message .. p
		else
			message = message:sub(n)
			return msg
		end
	end
end

function socket.write(msg)
	local pack = string.pack(">s2", msg)
	repeat
		local bytes, err = fd:send(pack)
		if not bytes then
			error(debug.traceback(err, 3))
		end
		pack = pack:sub(bytes+1)
	until pack == ""
end

return socket
