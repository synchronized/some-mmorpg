local PATH, IP, USERNAME, PASSWORD = ...

IP = IP or "127.0.0.1"
USERNAME = USERNAME or "sunday1"
PASSWORD = PASSWORD or "123456"

package.path = table.concat({
	PATH.."/client/?.lua",
	PATH.."/client/lualib/?.lua",
	PATH.."/common/?.lua",
	PATH.."/3rd/skynet/lualib/?.lua",
}, ";")
package.cpath = table.concat({
	PATH.."/client/luaclib/?.so",
	PATH.."/server/luaclib/?.so",
	PATH.."/3rd/skynet/luaclib/?.so",
}, ";")

local message = require "simplemessage"
local protoloader = require "protoloader"
local srp = require "srp"
local aes = require "aes"
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

local event = {}

function event:__error(what, err, req, session)
	print("error", what, err)
end

function event:ping()
	print("ping")
end

function event:signin(req, resp)
	print("signin", req.userid, resp.ok)
	if resp.ok then
		message.request "ping"	-- should error before login
		message.request "login"
	else
		-- signin failed, signup
		message.request("signup", { userid = "alice" })
	end
end

function event:signup(req, resp)
	print("signup", resp.ok)
	if resp.ok then
		message.request("signin", { userid = req.userid })
	else
		error "Can't signup"
	end
end

function event:request_shakehand()
	local private_key, public_key = srp.create_client_key ()
	user.private_key = private_key
	user.public_key = public_key
	message.request ("handshake", { username = user.username, client_pub = public_key })
end

function event:handshake (req, resp)
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

function event:auth (req, resp)
	local username = user.username

	user.login_session = resp.login_session
	local challenge = aes.encrypt (resp.challenge, user.session_key)
	message.request ("challenge", { 
		login_session = resp.login_session, 
		challenge = challenge,
	})
end

function event:challenge (req, resp)

	local token = aes.encrypt (resp.token, user.session_key)

	message.disconnect()
	message.register(protoloader.GAME)
	message.peer(IP, 9555)
	message.connect()

	message.request ("login", { 
		login_session = user.login_session,
		token = token,
	})

end

function event:login (req, resp)
	message.request ("character_list")
end

function event:character_list (req, resp)
end

message.register(protoloader.LOGIN)
message.peer(IP, 9777)
message.connect()
message.bind({}, event)

event:request_shakehand()

while true do
	message.update(1)
end
