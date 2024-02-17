local skynet = require "skynet"
local sharedata = require "skynet.sharedata"

local log = require "log"

local dbpacker = require "db.packer"
local cjsonutil = require "cjson.util"
local uuid = require "uuid"
local errcode = require "proto.errcode"

local handler = require "agent.handler"

local REQUEST = {}
handler = handler.new (REQUEST)

local user
local database
local gdd
local world

skynet.init(function () 
	database = skynet.uniqueservice ("database")
	gdd = sharedata.query ("gdd")
	world = skynet.uniqueservice ("world")
end)

handler:init (function (u)
	user = u
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

local function create (name, race, class)
	if not name then return { error_code = errcode.CHARACTER_INVLID_CHARACTER_NAME, } end	
	if not race then return { error_code = errcode.CHARACTER_INVLID_CHARACTER_RACE, } end
	if not class then return { error_code = errcode.CHARACTER_INVLID_CHARACTER_CLASS, } end
	if #name <= 2 or #name > 24 then
		log (string.format("invalid character name: %s", name))
		return { error_code = errcode.CHARACTER_INVLID_CHARACTER_NAME, }
	end
	if not gdd.race[race] then
		log (string.format("invalid character race: %s", race))
		return { error_code = errcode.CHARACTER_INVLID_CHARACTER_RACE, }
	end
	if not gdd.class[class] then
		log (string.format("invalid character class: %s", class))
		return { error_code = errcode.CHARACTER_INVLID_CHARACTER_CLASS, }
	end

	local race_info = gdd.race[race]

	local character = {
		general = {
			name = name,
			race = race,
			class = class,
			map = race_info.home,
		}, 
		attribute = {
			level = math.tointeger(1),
			exp = 0,
		},
		movement = {
			mode = 0,
			pos = { 
				x = race_info.pos_x,
				y = race_info.pos_y,
				z = race_info.pos_z,
				o = race_info.pos_o,
			 },
		},
	}
	return nil, character
end

local function on_enter_world (character)
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

function REQUEST:character_list ()
	local char_list = load_list (user.account_id)
	log ("<character_list> account_id: "..tostring(user.account_id)..", char_list: "..cjsonutil.serialise_value(char_list, "  "))
	local character = {}
	for _, character_id in pairs (char_list) do
		local c = skynet.call (database, "lua", "character", "load", character_id)
		if c then
			character[character_id] = dbpacker.unpack (c)
		end
	end

	log ("    character-list: "..cjsonutil.serialise_value(character, "  "))
	return nil, { character = character }
end

function REQUEST:character_create (args)
	if not args then
		return { error_code = errcode.COMMON_INVALID_REQUEST_PARMS }
	end
	if not args.character then
		return { error_code = errcode.COMMON_INVALID_REQUEST_PARMS }
	end
	local char_req = args.character

	log ("<character_create> args: "..cjsonutil.serialise_value(char_req, "  "))

	local ret, character = create(char_req.name, char_req.race, char_req.class)
	if ret then
		return ret -- 创建角色失败
	end

	local char_name = char_req.name
	local character_id = skynet.call(database, "lua", "character", "reserve", uuid.gen(), char_name)
	if not character_id then
		log ("    character_name: %s already exist", char_name)
		return { error_code = errcode.CHARACTER_INVLID_CHARACTER_ID }
	end

	character.id = character_id
	local json = dbpacker.pack (character)
	if not skynet.call(database, "lua", "character", "save", character_id, json) then
		log ("    character_id: %d save failed data: %s", character_id, json)
		return { error_code = errcode.CHARACTER_SAVE_DATA_FAILED }
	end

	local list = load_list (user.account_id)
	table.insert (list, character_id)
	json = dbpacker.pack (list)
	
	if not skynet.call(database, "lua", "character", "savelist", user.account_id, json) then
		log ("    account_id: %d save failed char_list: %s", user.account_id, json)
		return { error_code = errcode.CHARACTER_SAVE_DATA_FAILED }
	end

	return nil, { character = character }
end

function REQUEST:character_pick (args)
	if not args then
		return { error_code = errcode.COMMON_INVALID_REQUEST_PARMS }
	end
	if not args.id then
		log ("invalid character_id: %d", tonumber(args.id))
		return { error_code = errcode.CHARACTER_INVLID_CHARACTER_ID }
	end
	local character_id = args.id
	if not check_character (user.account_id, character_id) then
		log ("invalid character_id: %d", character_id)
		return { error_code = errcode.CHARACTER_INVLID_CHARACTER_ID }
	end

	log ("<character_pick> args: "..cjsonutil.serialise_value(args, "  "))

	if user.character then
 		log ("    current character_id: %d", user.character.id)
		-- 已经选择过角色, 如果是当前角色直接返回
		if user.character.id == character_id then
			return nil, { character = user.character }
		end

		-- 如果不是当前角色先将之前的角色离开地图
 		log ("    character_id: %d leave world", user.character.id)
		if user.map then
			skynet.call(user.map, "lua", "character_leave", user.character.id)
		end

		if user.world then
			skynet.call(user.world, "lua", "character_leave", user.character.id)
		end
	end

	local c = skynet.call(database, "lua", "character", "load", character_id)
	if not c then
		log ("character_id: %d load failed", character_id)
		return { error_code = errcode.CHARACTER_LOAD_DATA_FAILED }
	end	
	local character = dbpacker.unpack (c)
	user.character = character

	on_enter_world(user.character)
	local map = user.character.general.map
	local pos =  user.character.movement.pos
	skynet.call (world, "lua", "character_enter", character_id, map, pos)

	return nil, { character = character }
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