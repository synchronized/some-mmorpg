local skynet = require "skynet"
local errcode= require "proto.errcode"

local handler = require "agent.handler"

local log = require "log"

local REQUEST = {}
local user
handler = handler.new (REQUEST)

handler:init (function (u)
	user = u
end)

function REQUEST:map_ready ()
	local ok = skynet.call (user.map, "lua", "character_ready", user.character.movement.pos)
	if not ok then
		return { error_code = errcode.MAP_READY_FAILED }
	end
	return nil
end

function REQUEST:move (args)
	if not args then
		return { error_code = errcode.COMMON_INVALID_REQUEST_PARMS }
	end
	if not args.pos then
		return { error_code = errcode.MAP_INVALID_MOVE_POS }
	end

	local npos = args.pos
	local opos = user.character.movement.pos
	for k, v in pairs (opos) do
		if not npos[k] then
			npos[k] = v
		end
	end
	user.character.movement.pos = npos
	
	local ok = skynet.call (user.map, "lua", "move_blink", npos) 
	if not ok then
		user.character.movement.pos = opos
		log ("move failed ")
		return { error_code = errcode.MAP_MOVE_BLINK_FAILED, }
	end

	return nil, { pos = npos }
end

return handler
