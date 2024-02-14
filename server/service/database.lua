local skynet = require "skynet"
local redis = require "skynet.db.redis"

local config = require "config.database"
local account = require "db.account"
local character = require "db.character"

local center
local group = {}
local ngroup

local function hash_str (str)
	local hash = 0
	for c in string.gmatch(str, "(%w)") do
		hash = hash + string.byte (c)
	end
	return hash
end

local function hash_num (num)
	local hash = num << 8
	return hash
end

local function connection_handler (key)
	local hash
	local t = type (key)
	if t == "string" then
		hash = hash_str (key)
	else
		hash = hash_num (assert (tonumber (key)))
	end

	return group[hash % ngroup + 1]
end


local MODULE = {}
local function module_init (name, mod)
	MODULE[name] = mod
	mod.init (connection_handler)
end

local traceback = debug.traceback

skynet.start (function ()
	module_init ("account", account)
	module_init ("character", character)

	center = redis.connect (config.center)
	ngroup = #config.group
	for _, c in ipairs (config.group) do
		table.insert (group, redis.connect (c))
	end

	skynet.dispatch ("lua", function (_, _, mod, cmd, ...)
		local m = MODULE[mod]
		if not m then
			error(string.format("Unknown module: %s", tostring(mod)))
		end
		local f = m[cmd]
		if not f then
			error(string.format("Unknown module: %s command: %s", tostring(mod), tostring(cmd)))
		end
		
		local function ret (ok, ...)
			if not ok then
				local strerr = tostring(...)
				skynet.error("call db handle error : " .. strerr)
				skynet.ret ()
			else
				skynet.retpack (...)
			end
		end

		ret (xpcall (f, traceback, ...))
	end)
end)
