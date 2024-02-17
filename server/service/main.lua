local skynet = require "skynet"

local log = require "log"

local config = require "config.system"
local config_login = require "config.loginserver"

skynet.start(function()
	log ("Server start")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice ("debug_console", config.debug_port)
	skynet.uniqueservice ("protod")
	skynet.uniqueservice ("database")

	local loginserver = skynet.uniqueservice "loginserver"
	skynet.call(loginserver, "lua", "open", config_login)

	local hub = skynet.uniqueservice "hub"
	skynet.call(hub, "lua", "open", config_login)

	skynet.exit()
end)
