local sprotoloader = require "sprotoloader"
local sprotoparser = require "sprotoparser"
local io = io

local loader = {
	LOGIN = math.tointeger(1),
	GAME = math.tointeger(2),
}

local data = {
	[loader.LOGIN] = "login",
	[loader.GAME] = "game",
}

local indexbyname = {}

function loader.init ()
	local index = 0
	for protoid, protoname in ipairs(data) do
		local ftype = io.open(string.format("sproto/%s.type.sproto", protoname), "r")
		local strtype = ""
		if ftype then
			strtype = ftype:read "a"
			io.close(ftype)
		end

		local fc2s = io.open(string.format("sproto/%s.c2s.sproto", protoname), "r")
		local strc2s = ""
		if strc2s then
			strc2s = fc2s:read "a"
			io.close(fc2s)
		end

		local fs2c = io.open(string.format("sproto/%s.s2c.sproto", protoname), "r")
		local strs2c = ""
		if strs2c then
			strs2c = fs2c:read "a"
			io.close(fs2c)
		end
		sprotoloader.save (sprotoparser.parse (strtype..strc2s), index)
		sprotoloader.save (sprotoparser.parse (strtype..strs2c), index+1)

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
