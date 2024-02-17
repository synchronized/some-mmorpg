local skynet = require "skynet"

local log = {}

function log.print(...)
    skynet.error(tostring((...)))
end

function log.printf(fmt, ...)
	skynet.error(string.format(fmt, ...))
end

function log.__call(self, ...)
	if select("#", ...) == 1 then
		self.print(...)
	else
		self.printf(...)
	end
end

return setmetatable(log, log)
