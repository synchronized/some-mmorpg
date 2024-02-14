local skynet = require "skynet"
local sharedata = require "skynet.sharedata"

local syslog = require "syslog"
local dbpacker = require "db.packer"
local cjsonutil = require "cjson.util"
local handler = require "agent.handler"
local uuid = require "uuid"

local REQUEST = {}
handler = handler.new (REQUEST)

local user
local database
local gdd

handler:init (function (u)
	user = u
	database = skynet.uniqueservice ("database")
	gdd = sharedata.query "gdd"
end)

local function load_list (account_id)
	local char_list = skynet.call (database, "lua", "character", "list", account_id)
	if char_list then
		char_list = dbpacker.unpack (char_list)
	else
		char_list = {}
	end
	return char_list
end

local function check_character (account_id, character_id)
	local char_list = load_list (account_id)
	for _, v in pairs (char_list) do
		if tostring(v) == tostring(character_id) then return true end
	end
	return false
end

function REQUEST.character_list ()
	local char_list = load_list (user.account_id)
	skynet.error("<character_list> account_id: "..tostring(user.account_id)..", char_list: "..cjsonutil.serialise_value(char_list))
	local character = {}
	for _, character_id in pairs (char_list) do
		local c = skynet.call (database, "lua", "character", "load", character_id)
		if c then
			character[character_id] = dbpacker.unpack (c)
		end
	end

	skynet.error("    character-list: "..cjsonutil.serialise_value(character))
	return { character = character }
end

local function create (name, race, class)
	assert (name and race and class, "invalid name or race, class")
	assert (#name > 2 and #name < 24, string.format("invalid name: %s", name))
	assert (gdd.class[class], string.format("invalid class: %s", class))
	local r = assert(gdd.race[race], string.format("invalid race: %s", race))

	local character = {
		general = {
			name = name,
			race = race,
			class = class,
			map = r.home,
		}, 
		attribute = {
			level = math.tointeger(1),
			exp = 0,
		},
		movement = {
			mode = 0,
			pos = { x = r.pos_x, y = r.pos_y, z = r.pos_z, o = r.pos_o },
		},
	}
	return character
end

function REQUEST.character_create (args)
	assert(args, "invalid request")
	local char_req = assert(args.character, "invalid request character")

	skynet.error("<character_create> args: "..cjsonutil.serialise_value(char_req, "  "))

	local character = create(char_req.name, char_req.race, char_req.class)
	local character_id = skynet.call(database, "lua", "character", "reserve", tostring(uuid.gen()), char_req.name)
	if not character_id then
		skynet.error(string.format("    character_name: %s already exist", character.z.name))
		return {}
	end

	character.id = character_id
	local json = dbpacker.pack (character)
	if not skynet.call(database, "lua", "character", "save", character_id, json) then
		skynet.error(string.format("    character_id: %d save failed data: %s", character_id, json))	
	end

	local list = load_list (user.account_id)
	table.insert (list, character_id)
	json = dbpacker.pack (list)
	
	if not skynet.call(database, "lua", "character", "savelist", user.account_id, json) then
		skynet.error(string.format("    account_id: %d save failed char_list: %s", user.account_id, json))
	end

	skynet.error("    new character_info: "..cjsonutil.serialise_value(character, "      "))
	return { character = character }
end

function REQUEST.character_pick (args)
	assert(args, "invalid request")
	local character_id = assert(args.id, string.format("invalid request character_id"))
	assert(check_character (user.account_id, character_id), string.format("invalidid character_id: %d", character_id))

	skynet.error("<character_pick> args: "..cjsonutil.serialise_value(args, "  "))

	local c = assert(skynet.call(database, "lua", "character", "load", character_id), 
		string.format("character_id: %d load failed", character_id))
	local character = dbpacker.unpack (c)
	user.character = character

	local world = skynet.uniqueservice ("world")
	skynet.call (world, "lua", "character_enter", character_id)

	return { character = character }
end

function handler.on_enter_world (character)
	local temp_attribute = {
		[1] = {},
		[2] = {},
	}
	local attribute_count = #temp_attribute

	character.runtime = {
		temp_attribute = temp_attribute,
		attribute = temp_attribute[attribute_count],
	}

	local class = character.general.class
	local race = character.general.race
	local level = math.tointeger(character.attribute.level)

	
	local gda = gdd.attribute
	
	local base = temp_attribute[1]
	base.health_max = gda.health_max[class][level]
	base.strength = gda.strength[race][level]
	base.stamina = gda.stamina[race][level]
	base.attack_power = 0
	
	local last = temp_attribute[attribute_count - 1]
	local final = temp_attribute[attribute_count]

	if last.stamina >= 20 then
		final.health_max = last.health_max + 20 + (last.stamina - 20) * 10
	else
		final.health_max = last.health_max + last.stamina
	end
	final.strength = last.strength
	final.stamina = last.stamina
	final.attack_power = last.attack_power + final.strength

	local attribute = setmetatable (character.attribute, { __index = character.runtime.attribute })

	local health = attribute.health
	if not health or health > attribute.health_max then
		attribute.health = attribute.health_max
	end
end

function handler.save (character)
	if not character then return end

	local runtime = character.runtime
	character.runtime = nil
	local data = dbpacker.pack (character)
	character.runtime = runtime
	skynet.call (database, "lua", "character", "save", character.id, data)
end

return handler

