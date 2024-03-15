
THIRD_LIB_ROOT ?= 3rd

SKYNET_ROOT ?= $(THIRD_LIB_ROOT)/skynet
include $(SKYNET_ROOT)/platform.mk
LUA_ROOT ?= $(SKYNET_ROOT)/3rd/lua

CJSON_ROOT ?= $(THIRD_LIB_ROOT)/lua-cjson
CJSON_INC ?= ../skynet/3rd/lua

OPENSSL_ROOT ?= $(THIRD_LIB_ROOT)/openssl
OPENSSL_FLAG ?= -I$(OPENSSL_ROOT)/include -L$(OPENSSL_ROOT) -lcrypto

LSOCKET_ROOT ?= $(THIRD_LIB_ROOT)/lsocket
LSOCKET_INC ?= ../skynet/3rd/lua

BIN_PATH ?= bin

COMMON_ROOT ?= common
COMMON_LUA_CLIB_PATH ?= $(COMMON_ROOT)/luaclib

SERVER_ROOT ?= server
SERVER_LUA_CLIB_PATH ?= $(SERVER_ROOT)/luaclib
SERVER_CSERVICE_PATH ?= $(SERVER_ROOT)/cservice

CLIENT_ROOT ?= client
CLIENT_LUA_CLIB_PATH ?= $(CLIENT_ROOT)/luaclib

CUSTOM_CFLAGS = -g -O2 -Wall -I$(LUA_ROOT) $(MYCFLAGS)

# lua

LUA_STATICLIB := $(SKYNET_ROOT)/3rd/lua/liblua.a
LUA_LIB ?= $(LUA_STATICLIB)

# bin
BIN_OBJECT =

# common
COMMON_LUA_CLIB = cjson

# server
SERVER_LUA_CLIB = uuid
SERVER_CSERVICE = package

# client
CLIENT_LUA_CLIB = lsocket

all : \
  $(foreach v, $(BIN_OBJECT), $(BIN_PATH)/$(v)) \
  $(foreach v, $(COMMON_LUA_CLIB), $(COMMON_LUA_CLIB_PATH)/$(v).so) \
  $(foreach v, $(SERVER_LUA_CLIB), $(SERVER_LUA_CLIB_PATH)/$(v).so) \
  $(foreach v, $(SERVER_CSERVICE), $(SERVER_CSERVICE_PATH)/$(v).so) \
  $(foreach v, $(CLIENT_LUA_CLIB), $(CLIENT_LUA_CLIB_PATH)/$(v).so)

$(BIN_PATH) :
	mkdir $(BIN_PATH)

$(SERVER_CSERVICE_PATH) :
	mkdir $(SERVER_CSERVICE_PATH)

$(SERVER_LUA_CLIB_PATH) :
	mkdir $(SERVER_LUA_CLIB_PATH)

$(CLIENT_LUA_CLIB_PATH) :
	mkdir $(CLIENT_LUA_CLIB_PATH)

$(COMMON_LUA_CLIB_PATH)/cjson.so : | $(COMMON_LUA_CLIB_PATH)
	cd $(CJSON_ROOT) && $(MAKE) LUA_INCLUDE_DIR=$(CJSON_INC) CC=$(CC) CJSON_LDFLAGS="$(SHARED)" && cd - && cp $(CJSON_ROOT)/cjson.so $@

$(CLIENT_LUA_CLIB_PATH)/lsocket.so : | $(CLIENT_LUA_CLIB_PATH)
	cd $(LSOCKET_ROOT) && $(MAKE) LUA_INCLUDE=$(LSOCKET_INC) && cd - && cp $(LSOCKET_ROOT)/lsocket.so $@

$(SERVER_CSERVICE_PATH)/package.so : $(SERVER_ROOT)/service-src/service_package.c | $(SERVER_CSERVICE_PATH)
	$(CC) $(CUSTOM_CFLAGS) $(SHARED) $< -o $@ -I$(SKYNET_ROOT)/skynet-src

$(SERVER_LUA_CLIB_PATH)/srp.so : $(SERVER_ROOT)/lualib-src/lua-srp.c | $(SERVER_LUA_CLIB_PATH)
	$(CC) $(CUSTOM_CFLAGS) $(SHARED) $^ $(OPENSSL_FLAG) -o $@

$(SERVER_LUA_CLIB_PATH)/aes.so : $(SERVER_ROOT)/lualib-src/lua-aes.c | $(SERVER_LUA_CLIB_PATH)
	$(CC) $(CUSTOM_CFLAGS) $(SHARED) $^ $(OPENSSL_FLAG) -o $@

$(SERVER_LUA_CLIB_PATH)/uuid.so : $(SERVER_ROOT)/lualib-src/lua-uuid.c | $(SERVER_LUA_CLIB_PATH)
	$(CC) $(CUSTOM_CFLAGS) $(SHARED) $^ $(OPENSSL_FLAG) -o $@


clean :
	rm -f $(COMMON_LUA_CLIB_PATH)/*.so $(SERVER_LUA_CLIB_PATH)/*.so $(SERVER_CSERVICE_PATH)/*.so $(CLIENT_LUA_CLIB_PATH)/*.so

cleanall_cjson : 
	cd $(CJSON_ROOT) && $(MAKE) clean

cleanall_lsocket : 
	cd $(LSOCKET_ROOT) && $(MAKE) clean

cleanall : clean cleanall_cjson cleanall_lsocket
