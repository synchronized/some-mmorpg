local config = {
	port = 9777,
	nwork = 8,
	auth_timeout = 10, -- seconds
	session_expire_time = 30 * 60, -- seconds
	islogmsg = false, --是否需要记录请求响应日志
}

return config
