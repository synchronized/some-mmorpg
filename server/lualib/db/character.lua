local skynet = require "skynet"

local cjsonutil = require "cjson.util"

local character = {}
local connection_handler

local function hash_str (str)
	local hash = 0
	for c in string.gmatch(str, "(%w)") do
		hash = hash + string.byte (c)
	end
	return hash
end

function character.init (ch)
	connection_handler = ch
end

local function make_list_key (account_id)
	local major = account_id // 100
	local minor = account_id % 100
	return connection_handler (account_id), string.format ("user-characterids:%d", major), minor
end

local function make_character_key (character_id)
	local major = character_id // 100
	local minor = character_id % 100
	return connection_handler (character_id), string.format ("character:%d", major), minor
end

local function make_name_key (name)
	local hash_val = hash_str(name)
	local major = hash_val // 100
	local minor = hash_val % 100
	return connection_handler (name), "char-name:"..major, name
end

function character.reserve (character_id, name)
	local connection, key, field = make_name_key (name)
	if connection:hsetnx (key, field, character_id) == 0 then
		return
	end
	return character_id
end

function character.save (character_id, data)
	local connection, key, field = make_character_key (character_id)
	return connection:hset (key, field, data)
end

function character.load (character_id)
	local connection, key, field = make_character_key (character_id)
	return connection:hget (key, field)
end

function character.list (account_id)
	local connection, key, field = make_list_key (account_id)
	return connection:hget (key, field)
end

function character.savelist (account_id, data)
	local connection, key, field = make_list_key (account_id)
	return connection:hset (key, field, data)
end

return character

