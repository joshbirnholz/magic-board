#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${XMAGE_HOME:?Set XMAGE_HOME to your extracted xmage directory}"
: "${RULES_BRIDGE_TOKEN:?Set RULES_BRIDGE_TOKEN to a private connection key}"
[ -f build/magicboard-rules.jar ] || { echo 'The bridge jar is missing. Build it first or extract the complete bridge bundle.' >&2; exit 1; }
[ -f "$XMAGE_HOME/mage-client/lib/mage-client-1.4.63.jar" ] || { echo 'XMAGE_HOME must contain the matching mage-client and mage-server directories.' >&2; exit 1; }
exec java -Xmx512m --add-opens=java.base/java.io=ALL-UNNAMED -Djava.awt.headless=true -Dfile.encoding=UTF-8 -cp "build/magicboard-rules.jar:lib/*:$XMAGE_HOME/mage-client/lib/*" magicboard.rules.BridgeMain "$@"
