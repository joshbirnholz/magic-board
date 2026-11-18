#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${XMAGE_HOME:?Set XMAGE_HOME to your extracted xmage directory}"
: "${RULES_BRIDGE_TOKEN:?Set RULES_BRIDGE_TOKEN to a private connection key}"
exec java -Xmx512m --add-opens=java.base/java.io=ALL-UNNAMED -Djava.awt.headless=true -cp "build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" magicboard.rules.BridgeMain "$@"
