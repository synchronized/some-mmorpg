#!/bin/sh
#
CURRDIR=$(cd "$(dirname "$0")";pwd)
PROJECTDIR=$(dirname "${CURRDIR}")

$PROJECTDIR/3rd/skynet/3rd/lua/lua $PROJECTDIR/client/simpleclient.lua $PROJECTDIR $1

