local sprotoloader = require "sprotoloader"
local cjsonutil = require "cjson.util"

local loader = {
	LOGIN = math.tointeger(1),
	GAME = math.tointeger(2),
}

local data = {
	[loader.LOGIN] = require "proto.login",
	[loader.GAME] = require "proto.game",
}

local indexbyname = {}

function loader.init ()
	local index = 0
	for protoid, proto in ipairs(data) do
		sprotoloader.save(proto.c2s, index)
		sprotoloader.save(proto.c2s, index+1)
		indexbyname[protoid] = index
		index = index + 2
	end
end

local function indexbyside(isServer, index)
	if isServer then
		return index, index+1
	else
		return index+1, index
	end
end

local function loadbyside(isServer, index)
	local host_ndex, attach_ndex = indexbyside(isServer, index)
	local host = sprotoloader.load (host_ndex):host "package"
	local request = host:attach (sprotoloader.load (attach_ndex))
	return host, request
end

function loader.getindexbyname (name)
	return indexbyname[name]
end

function loader.loadbyserver (index)
	return loadbyside(true, index)
end

function loader.loadbyclient (index)
	return loadbyside(false, index)
end

return loader
