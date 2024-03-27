#!/bin/bash

export SERVER_NAME=smmo
export OS=$(uname -s)

CURRDIR=$(cd "$(dirname "$0")";pwd)
PROJECTDIR=$(dirname "${CURRDIR}")

#编译协议
protoc --proto_path=proto/protobuf/source --descriptor_set_out=proto/protobuf/pb/protocol.pb proto/protobuf/source/*.proto

${PROJECTDIR}/3rd/skynet/skynet ${PROJECTDIR}/server/config-pb
