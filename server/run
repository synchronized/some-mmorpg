#!/bin/bash

export SERVER_NAME=smmo
export OS=$(uname -s)

CURRDIR=$(cd "$(dirname "$0")";pwd)
PROJECTDIR=$(dirname "${CURRDIR}")

cd ${PROJECTDIR}/server

${PROJECTDIR}/3rd/skynet/skynet config
