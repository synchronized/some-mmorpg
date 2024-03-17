local errcode = {
	SUCCESS = 0, -- 操作成功

	-- 公共错误
	COMMON_INVALID_REQUEST_PARMS = 100, -- 请求参数有误
	COMMON_SERVER_ERROR = 101, -- 服务器出错

	-- 登陆错误
	LOGIN_INVALID_USERNAME = 10001, -- username 有误
	LOGIN_INVALID_CLIENT_PUB = 10002, -- client_pub 有误
	LOGIN_INVALID_CHALLENGE = 10003, -- challenge 有误
	LOGIN_INVALID_SESSION_ID = 10004, -- session_id 有误
	LOGIN_CHALLENGE_VERIFY_FAILED = 10005, -- challenge 验证失败
	LOGIN_SESSION_TIMEOUT = 10006, -- 会话超时
	LOGIN_INVALID_HMAC = 10007, -- hmac 有误
	LOGIN_INVALID_PASSWORD = 10008, -- password 有误
	LOGIN_INVALID_USERNAME_OR_PASSWORD = 10009, -- username 或者 password 有误
	LOGIN_INVALID_HANDLE_TYPE = 10010, -- 请求协议有误

	CHARACTER_INVLID_CHARACTER_ID = 20001, -- character_id 有误
	CHARACTER_INVLID_CHARACTER_NAME = 20002, -- character name 有误
	CHARACTER_INVLID_CHARACTER_RACE = 20003, -- character 种族/阵营有误
	CHARACTER_INVLID_CHARACTER_CLASS = 20004, -- character 职业有误
	CHARACTER_SAVE_DATA_FAILED = 20005, -- 保存数据失败
	CHARACTER_LOAD_DATA_FAILED = 20006, -- 加载数据失败

	MAP_INVALID_MOVE_POS = 30001, -- 移动地点有误
	MAP_READY_FAILED = 30002, -- 加入地图失败
	MAP_MOVE_BLINK_FAILED = 30003, -- 地图移动失败

	COMBAT_INVALID_TARGET = 40001, -- 攻击目标有误
	COMBAT_TARGET_HAS_GONE = 40002, -- 目标不存在
}

local errmsg = {
	[errcode.SUCCESS] = "操作成功",

	[errcode.COMMON_INVALID_REQUEST_PARMS] = "请求参数有误",
	[errcode.COMMON_SERVER_ERROR] = "服务器出错",

	[errcode.LOGIN_INVALID_USERNAME] = "username 有误",
	[errcode.LOGIN_INVALID_CLIENT_PUB] = "client_pub 有误",
	[errcode.LOGIN_INVALID_CHALLENGE] = "challenge 有误",
	[errcode.LOGIN_INVALID_SESSION_ID] = "session_id 有误",
	[errcode.LOGIN_CHALLENGE_VERIFY_FAILED] = "challenge 验证失败",
	[errcode.LOGIN_SESSION_TIMEOUT] = "会话超时",
	[errcode.LOGIN_INVALID_HMAC] = "hmac 有误",
	[errcode.LOGIN_INVALID_PASSWORD] = "password 有误",
	[errcode.LOGIN_INVALID_USERNAME_OR_PASSWORD] = "username 或者 password 有误",
	[errcode.LOGIN_INVALID_HANDLE_TYPE] = "请求协议有误",

	[errcode.CHARACTER_INVLID_CHARACTER_ID] = "character_id 有误",
	[errcode.CHARACTER_INVLID_CHARACTER_NAME] = "character name 有误",
	[errcode.CHARACTER_INVLID_CHARACTER_RACE] = "character 种族/阵营有误",
	[errcode.CHARACTER_INVLID_CHARACTER_CLASS] = "character 职业有误",
	[errcode.CHARACTER_SAVE_DATA_FAILED] = "保存数据失败",
	[errcode.CHARACTER_LOAD_DATA_FAILED] = "加载数据失败",

	[errcode.MAP_MOVE_BLINK_FAILED] = "地图移动失败",
}

function errcode.error_msg(err_code)
	return errmsg[err_code] or "<unknow error>"
end

return errcode
