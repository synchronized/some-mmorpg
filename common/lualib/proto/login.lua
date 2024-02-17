local sparser = require "sprotoparser"

local login_proto = {}

login_proto.c2s = sparser.parse [[

.result {
    error_code 0 : integer             # error code
}

.package {
    type 0 : integer
    session 1 : integer
    ud 2 : result
}

handshake 1 {
    request {
        username 0 : string            # username        
        client_pub 1 : string          # srp argument, client public key, known as 'A'
    }
    response {
        user_exists 1 : boolean        # 'true' if username is already used
        salt 2 : string                # srp argument, salt, known as 's'
        server_pub 3 : string          # srp argument, server public key, known as 'B'
        challenge 4 : string           # login session challenge
    }
}

auth 2 {
    request {
        challenge 0 : string           # encrypted challenge
        password 1 : string            # encrypted password. send this ONLY IF you're registrying new account
    }
    response {
        login_session 1 : integer      # login session id, needed for further use
        expire 2 : integer             # login session expire time, in second
        challenge 3 : string           # token request challenge
    }
}

challenge 3 {
    request {
        login_session 0 : integer      # login session id
        challenge 1 : string           # encryped challenge
    }
    response {
        token 1 : string               # login token
        challenge 2 : string           # next token challenge
    }
}

]]

login_proto.s2c = sparser.parse [[
.package {
    type 0 : integer
    session 1 : integer
}
]]

return login_proto
