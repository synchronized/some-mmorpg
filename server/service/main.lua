local skynet = require "skynet"

local log = require "log"

local config = require "config.system"
local config_login = require "config.loginserver"
local config_manager = require "config.managerserver"

skynet.start(function()
	log ("Server start")
	if not skynet.getenv "daemon" then
		skynet.newservice("console")
	end
	skynet.newservice ("debug_console", config.debug_port)
	skynet.uniqueservice ("protod")
	skynet.uniqueservice ("database")

	local loginserver = skynet.uniqueservice "loginserver"
	skynet.call(loginserver, "lua", "open", config_login)

	local manager = skynet.uniqueservice "manager"
	skynet.call(manager, "lua", "open", config_manager) --创建agent池

	local hub = skynet.uniqueservice "hub"
	skynet.call(hub, "lua", "open", config_login) --开始监听端口

	skynet.exit()
end)
