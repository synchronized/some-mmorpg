local skynet = require "skynet"

local protoloader = require "proto/sproto_mgr"

protoloader.init ()

local protod = {}

function protod.loadindex(name)
	return protoloader.getindexbyname(name)
end

skynet.start (function ()
	skynet.dispatch("lua", function (_, _, cmd, ...)
		local f = protod[cmd]
		if not f then
			error(string.format("Unknown command %s", tostring(cmd)))
		end

		skynet.retpack(f(...))
	end)
end)
