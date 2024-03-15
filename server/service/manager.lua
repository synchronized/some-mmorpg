local skynet = require "skynet"

local service = require "service"
local client = require "client"
local log = require "log"
local protoloader = require "protoloader"

local cjsonutil = require "cjson.util"

local traceback = debug.traceback

local manager = {}
local users = {}

local agent_pool = {}

local function new_agent()
	-- handle the agent
	local agent
	if #agent_pool == 0 then
		agent = skynet.newservice ("agent", skynet.self())
		log.printf ("pool is empty, new agent(%d) created", agent)
	else
		agent = table.remove (agent_pool, 1)
		log.printf ("agent(%d) assigned, %d remain in pool", agent, #agent_pool)
	end
	return agent
end

local function free_agent(agent)
	-- kill agent, todo: put it into a pool maybe better
	table.insert (agent_pool, agent)
end

function manager.open(conf)
	local selfaddr = skynet.self ()
	local n = tonumber(conf.agent_pool or 8)
	log ("manager.open agent pool size: %d", n)
	for _ = 1, n do
		table.insert (agent_pool, skynet.newservice ("agent", selfaddr))
	end
end

function manager.assign(fd, account_id)
	-- assign agent
	local agent
	repeat
		agent = users[account_id]
		if not agent then
			agent = new_agent()
			if not users[account_id] then
				-- double check
				users[account_id] = agent
			else
				free_agent(agent)
				agent = users[account_id]
			end
		end
	until skynet.call(agent, "lua", "assign", fd, account_id)
	log("Assign %d to %s [%s]", fd, account_id, agent)
end

function manager.kick(account_id)
	log ("manager.kick account_id: %d", account_id)
	local agent = users[account_id]
	assert(agent)
	skynet.call(agent, "lua", "close")
end

function manager.exit(account_id)
	log ("manager.exit account_id: %d", account_id)
	local agent = users[account_id]
	assert(agent)
	users[account_id] = nil
	free_agent(agent)
end

service.init {
	command = manager,
	info = users,
	require = {
		"loginserver",
		"gdd",
		"world"
	},
	init = client.init (protoloader.GAME),
}
