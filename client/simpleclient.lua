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

local message = require "simplemessage"
local protoloader = require "protoloader"
local srp = require "srp"
local aes = require "aes"
local cjsonutil = require "cjson.util"
local lsocket = require "lsocket"
local tableext = require "somemmo.tableext"

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

function event:request_shakehand()
	local private_key, public_key = srp.create_client_key ()
	user.private_key = private_key
	user.public_key = public_key
	message.request ("handshake", { username = user.username, client_pub = public_key })
end

function event:handshake (req, resp, ret)
	if ret then
		print(string.format("<error> RESPONSE.handshake ret:", cjsonutil.serialise_value(ret)))
		return
	end

	local username = user.username

	if resp.user_exists then
		local key = srp.create_client_session_key (username, user.password, resp.salt, user.private_key, user.public_key, resp.server_pub)
		user.session_key = key
		local ret = { 
			challenge = aes.encrypt (resp.challenge, key),
		}
		message.request ("auth", ret)
	else
		local key = srp.create_client_session_key (username, user.password, resp.salt, user.private_key, user.public_key, resp.server_pub)
		user.session_key = key
		local ret = { 
			challenge = aes.encrypt (resp.challenge, key), 
			password = aes.encrypt (user.password, key),
		}
		message.request ("auth", ret)
	end
end

function event:auth (req, resp, ret)
	if ret then
		print(string.format("<error> RESPONSE.auth ret:", cjsonutil.serialise_value(ret)))
		return
	end

	local username = user.username

	user.login_session = resp.login_session
	local challenge = aes.encrypt (resp.challenge, user.session_key)
	message.request ("challenge", { 
		login_session = resp.login_session, 
		challenge = challenge,
	})
end

function event:challenge (req, resp, ret)
	if ret then
		print(string.format("<error> RESPONSE.challenge ret:", cjsonutil.serialise_value(ret)))
		return
	end

	user.token = aes.encrypt (resp.token, user.session_key)

	message.register(protoloader.GAME)
	self.authed = true

	message.request ("character_list")
end

function event:character_list (req, resp, ret)
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

function event:character_create (req, resp, ret)
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

event:request_shakehand()

while true do
	message.update(5)
	cli:update()
end
