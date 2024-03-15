
local account = {}
local connection_handler

function account.init (ch)
	connection_handler = ch
end

local function make_key (username)
	return connection_handler (username), string.format ("user:%s", username)
end

function account.load (username)
	assert (username, "invalid username")

	local acc = { username = username }

	local connection, key = make_key (username)
	if connection:exists (key) then
		acc.account_id = connection:hget (key, "account_id")
		acc.password = connection:hget (key, "password")
	end

	return acc
end

function account.create (account_id, username, password)
	assert (account_id, "invalid account_id")
	assert (username, "invalid username")
	assert (#username < 24, string.format("account_id:%d invalid username: %s", account_id, username))
	assert (password, "invalid password")
	assert (#password < 24, string.format("account_id:%d invalid password: %s", account_id, password))

	local connection, key = make_key (username)
	assert (connection:hsetnx (key, "account_id", account_id) ~= 0,
		string.format("account_id: %d create account failed ", account_id))

	assert (connection:hmset (key, "password", password) ~= 0,
		string.format("account_id: %d save account password failed", account_id))

	return account_id
end

return account
