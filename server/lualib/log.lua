local skynet = require "skynet"

local log = {}

function log.print(...)
    skynet.error(tostring((...)))
end

function log.printf(fmt, ...)
	skynet.error(string.format(fmt, ...))
end

return log
