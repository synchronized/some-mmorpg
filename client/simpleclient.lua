local PATH, IP, USERNAME, PASSWORD = ...

IP = IP or "127.0.0.1"
USERNAME = USERNAME or "sunday1"
PASSWORD = PASSWORD or "123456"

package.path = table.concat({
		PATH.."/client/lualib/?.lua",
		PATH.."/common/lualib/?.lua",
		PATH.."/3rd/skynet/lualib/?.lua",
}, ";")
package.cpath = table.concat({
		PATH.."/client/luaclib/?.so",
		PATH.."/common/luaclib/?.so",
		PATH.."/server/luaclib/?.so",
		PATH.."/3rd/skynet/luaclib/?.so",
}, ";")

local crypt = require "client.crypt"
local protoloader = require "proto/sproto_mgr"
local message = require "simplemessage"
local cjsonutil = require "cjson.util"

protoloader.init()

local user = { username = USERNAME, password = PASSWORD }

do
	if not user.username then
		print([[Usage:
			lua client/simpleclient.lua <ip> <username> <password>
		]])
		return
	end
end

local event = {
	authed = false
}

function event:ping()
end

function event:acknowledgment (args)
	user.acknumber = args.acknumber
	user.clientkey = crypt.randomkey()
	message.request ("handshake", {
						 client_pub = crypt.dhexchange(user.clientkey),
	})
end


function event:handshake(_, resp, ret)
	if ret then
		print(string.format("<error> RESPONSE.handshake ret:", cjsonutil.serialise_value(ret)))
		return
	end
	user.secret = crypt.dhsecret(resp.secret, user.clientkey)
	print("sceret is ", crypt.hexencode(user.secret))

	local hmac = crypt.hmac64(user.acknumber, user.secret)
	message.request("challenge", {
						hmac = hmac,
	})
end

function event:challenge(_, _, ret)
	if ret then
		print(string.format("<error> RESPONSE.challenge ret:", cjsonutil.serialise_value(ret)))
		return
	end
	message.request("auth", {
						username = crypt.desencode (user.secret, user.username),
						password = crypt.desencode (user.secret, user.password),
	})
end

function event:auth(_, resp, ret)
	if ret then
		print(string.format("<error> RESPONSE.auth ret:", cjsonutil.serialise_value(ret)))
		return
	end

	user.login_session = resp.login_session
	user.login_session_expire = resp.expire
	user.token = resp.token

	-- 跳转到游戏服务器
	message.request ("switchgame")

	message.register(protoloader.GAME)
	self.authed = true

	-- 请求角色列表
	message.request ("character_list", {})
end

function event:character_list (_, resp, ret)
	if ret then
		print(string.format("<error> RESPONSE.character_list ret:", cjsonutil.serialise_value(ret)))
		return
	end

	local character_id = next(resp.character)
	print(string.format("choose characterId: %s", tostring(character_id)))
	if not character_id then
		message.request("character_create", {
			character = {
				name = string.format("%s-%s", user.username, "hello"),
				race = "human",
				class = "warrior" ,
			},
		})
	else
		message.request("character_pick", {
			id = character_id,
		})
	end
end

function event:character_create (_, _, ret)
	if ret then
		print(string.format("<error> RESPONSE.character_create ret:", cjsonutil.serialise_value(ret)))
		return
	end

	message.request ("character_list")
end

local cli = {
	authed = false,
	pingtime = os.time()
}
function cli:update()
	if self.authed then
		local timenow = os.time()
		if timenow - self.pingtime > 5 then
			self.pingtime = timenow
			message.request("ping")
		end
	end
end

message.register(protoloader.LOGIN)
message.peer(IP, 9777)
message.connect()
message.bind(cli, event)

while true do
	message.update(5)
	cli:update()
end
