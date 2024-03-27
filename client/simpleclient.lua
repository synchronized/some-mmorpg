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
local errcode = require "errcode.errcode"

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

function event:res_acknowledgment (args)
	user.acknumber = args.acknumber
	user.clientkey = crypt.randomkey()
	message.sendmsg ("req_handshake", {
						 client_pub = crypt.dhexchange(user.clientkey),
	})
end

local cb_handshake = function(req, opflag, error_code)
	if not opflag then
		print(string.format("<error> RESPONSE.handshake errcode:%d(%s)", error_code, errcode.error_msg(error_code)))
		return
	end
	message.sendmsg("req_auth", {
						username = crypt.desencode (user.secret, user.username),
						password = crypt.desencode (user.secret, user.password),
	})
end

function event:res_handshake(resp)
	if not resp then
		print(string.format("<error> RESPONSE.handshake resp is nil:"))
		return
	end
	user.secret = crypt.dhsecret(resp.secret, user.clientkey)
	print("sceret is ", crypt.hexencode(user.secret))

	local hmac = crypt.hmac64(user.acknumber, user.secret)
	message.sendmsg("req_challenge", {
						hmac = hmac,
									 }, cb_handshake)
end

function event:res_auth(resp)
	if not resp then
		print(string.format("<error> RESPONSE.auth resp is nil:"))
		return
	end

	user.login_session = resp.login_session
	user.login_session_expire = resp.expire
	user.token = resp.token

	-- 跳转到游戏服务器
	message.sendmsg ("req_switchgame", nil)

	--message.register(protoloader.GAME)
	self.authed = true

	-- 请求角色列表
	message.sendmsg ("req_character_list", nil)
end

function event:res_character_list (resp)
	resp = resp or {}

	local character_id = next(resp.character)
	print(string.format("choose characterId: %s", tostring(character_id)))
	if not character_id then
		message.sendmsg("req_character_create", {
			character = {
				name = string.format("%s-%s", user.username, "hello"),
				race = "human",
				class = "warrior" ,
			},
		})
	else
		message.sendmsg("req_character_pick", {
							id = character_id,
		})
	end
end

function event:res_character_create ()
	message.sendmsg ("req_character_list")
end

function event:res_character_pick (resp)
	print(string.format("<== RESPONSE res_character_pick character: %s",
						cjsonutil.serialise_value(resp)))
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
			message.sendmsg("ping")
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
